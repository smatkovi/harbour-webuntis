"""
Sailfish Secrets integration for secure credential storage.
Uses D-Bus to communicate with the Sailfish Secrets daemon via P2P socket.

Architecture:
1. Discovery Service on Session Bus gives us the P2P socket address
2. We connect directly to the P2P socket to talk to the real daemon
3. We use call_blocking for P2P D-Bus (no bus name needed)
"""

import json

try:
    import dbus
    import dbus.connection
    HAS_DBUS = True
except ImportError:
    HAS_DBUS = False

# Collection and secret names
COLLECTION_NAME = "WebUntisWallet4"  # v4 - separate collection for normal version
SECRET_USER_CREDS = "user-credentials"
SECRET_TRAP_CREDS = "trap-credentials"

# Default encrypted storage plugin (used by Sailtrix)
DEFAULT_PLUGIN = "org.sailfishos.secrets.plugin.encryptedstorage.sqlcipher"

# UserInteractionMode enum values
USER_INTERACTION_PREVENT = 0  # No UI - use if device is unlocked
USER_INTERACTION_SYSTEM = 2   # System UI for authentication

# Use SystemInteraction to allow system UI for authentication (like Sailtrix does)
USER_INTERACTION_MODE = USER_INTERACTION_SYSTEM

# DeviceLockUnlockSemantic enum
DEVICE_LOCK_KEEP_UNLOCKED = 0  # Stay unlocked after device unlock

# AccessControlMode enum  
ACCESS_CONTROL_OWNER_ONLY = 0

def log(msg):
    """Log helper"""
    try:
        import pyotherside
        pyotherside.send('log', f'[Secrets] {msg}')
    except:
        print(f"[Secrets] {msg}")


class SailfishSecrets:
    """Interface to Sailfish Secrets via P2P D-Bus socket"""
    
    def __init__(self):
        self.available = False
        self.p2p_connection = None
        self.plugin_name = DEFAULT_PLUGIN
        self._init_connection()
    
    def _init_connection(self):
        """Initialize connection to Sailfish Secrets daemon"""
        if not HAS_DBUS:
            log("D-Bus module not available")
            return
        
        try:
            # Step 1: Get P2P socket address from Discovery Service
            session_bus = dbus.SessionBus()
            
            discovery_obj = session_bus.get_object(
                'org.sailfishos.secrets.daemon.discovery',
                '/Sailfish/Secrets/Discovery'
            )
            discovery_iface = dbus.Interface(
                discovery_obj,
                'org.sailfishos.secrets.daemon.discovery'
            )
            
            # Get the P2P socket address
            p2p_address = str(discovery_iface.peerToPeerAddress())
            log(f"P2P socket: {p2p_address}")
            
            # Step 2: Connect to P2P socket using low-level connection
            self.p2p_connection = dbus.connection.Connection(p2p_address)
            log("Connected to P2P socket")
            
            # Test connection and get plugins
            self._get_plugins()
            
            self.available = True
            log("Sailfish Secrets ready!")
            
        except dbus.exceptions.DBusException as e:
            log(f"D-Bus error: {e}")
            self.available = False
        except Exception as e:
            log(f"Error: {e}")
            import traceback
            log(traceback.format_exc())
            self.available = False
    
    def _call(self, method, signature, *args):
        """Make a D-Bus call on the P2P connection"""
        return self.p2p_connection.call_blocking(
            None,  # bus_name - None for P2P
            '/Sailfish/Secrets',  # object_path
            'org.sailfishos.secrets',  # interface
            method,  # method name
            signature,  # signature
            args  # arguments as tuple
        )
    
    def _get_plugins(self):
        """Get available plugins and select best one"""
        try:
            result = self._call('getPluginInfo', '')
            # result is (Result, storagePlugins, encryptionPlugins, encryptedStoragePlugins, authPlugins)
            result_tuple = result[0]
            encrypted_storage_plugins = result[3]
            
            log(f"getPluginInfo result: code={result_tuple[0]}")
            
            if encrypted_storage_plugins:
                for plugin in encrypted_storage_plugins:
                    plugin_name = str(plugin[0])
                    log(f"Available plugin: {plugin_name}")
                    if 'sqlcipher' in plugin_name:
                        self.plugin_name = plugin_name
                        break
            
            log(f"Using plugin: {self.plugin_name}")
            
        except Exception as e:
            log(f"getPluginInfo error: {e}")
    
    def _create_collection_if_needed(self):
        """Ensure our collection exists"""
        if not self.available:
            return False
        
        try:
            # createCollection: sss(i)(i) -> (iis)
            # collectionName, storagePluginName, encryptionPluginName, unlockSemantic, accessControlMode
            result = self._call(
                'createCollection',
                'sss(i)(i)',
                COLLECTION_NAME,
                self.plugin_name,
                self.plugin_name,
                (DEVICE_LOCK_KEEP_UNLOCKED,),
                (ACCESS_CONTROL_OWNER_ONLY,)
            )
            
            code = int(result[0])
            error_code = int(result[1])
            message = str(result[2])
            
            if code == 0:
                log(f"Collection '{COLLECTION_NAME}' created")
                return True
            elif 'already exists' in message.lower() or error_code == 3:
                log(f"Collection already exists - OK")
                return True
            else:
                log(f"createCollection failed: code={code}, error={error_code}, msg={message}")
                return False
                
        except dbus.exceptions.DBusException as e:
            if 'already exists' in str(e).lower():
                log(f"Collection already exists - OK")
                return True
            log(f"createCollection error: {e}")
            return False
    
    def store_secret(self, name: str, data: dict) -> bool:
        """Store a secret securely - deletes existing secret first to allow updates"""
        if not self.available:
            log("Secrets not available")
            return False
        
        if not self._create_collection_if_needed():
            return False
        
        # DELETE existing secret first (Sailfish Secrets doesn't support UPDATE)
        try:
            self._call(
                'deleteSecret',
                '(sss)(i)s',
                (name, COLLECTION_NAME, self.plugin_name),
                (USER_INTERACTION_MODE,),
                ""
            )
            log(f"Deleted existing secret '{name}' for update")
        except:
            pass  # Secret probably didn't exist, that's fine
        
        json_data = json.dumps(data).encode('utf-8')
        
        try:
            # setSecret signature: ((sss)aya{sv})(ssss(i)sa{is}(i)(i))(i)s
            # - secret: ((sss)aya{sv}) - identifier, data, filterData
            # - uiParams: (ssss(i)sa{is}(i)(i))
            # - userInteractionMode: (i)
            # - interactionServiceAddress: s
            
            # Build the secret tuple
            secret = (
                (name, COLLECTION_NAME, self.plugin_name),  # identifier
                json_data,  # data as bytes
                {}  # filterData - empty dict
            )
            
            # Build uiParams - all empty/defaults
            ui_params = (
                "",  # secretName
                "",  # collectionName
                "",  # pluginName
                "",  # applicationId
                (0,),  # operation
                "",  # authenticationPluginName
                {},  # promptText
                (0,),  # inputType
                (0,)  # echoMode
            )
            
            result = self._call(
                'setSecret',
                '((sss)aya{sv})(ssss(i)sa{is}(i)(i))(i)s',
                secret,
                ui_params,
                (USER_INTERACTION_MODE,),
                ""  # interactionServiceAddress
            )
            
            code = int(result[0])
            error_code = int(result[1])
            message = str(result[2])
            
            if code == 0:
                log(f"Stored secret '{name}'")
                return True
            else:
                log(f"setSecret failed: code={code}, error={error_code}, msg={message}")
                return False
                
        except dbus.exceptions.DBusException as e:
            log(f"Store error: {e}")
            return False
    
    def retrieve_secret(self, name: str) -> dict:
        """Retrieve a secret"""
        if not self.available:
            log("Secrets not available")
            return None
        
        try:
            # getSecret signature: (sss)(i)s
            # - identifier: (sss)
            # - userInteractionMode: (i)
            # - interactionServiceAddress: s
            
            result = self._call(
                'getSecret',
                '(sss)(i)s',
                (name, COLLECTION_NAME, self.plugin_name),
                (USER_INTERACTION_MODE,),
                ""
            )
            
            # result[0] is Result (code, errorCode, message)
            # result[1] is Secret ((sss)aya{sv})
            result_tuple = result[0]
            code = int(result_tuple[0])
            error_code = int(result_tuple[1])
            message = str(result_tuple[2])
            
            if code == 0:
                secret = result[1]
                # secret[1] is the data (byte array)
                data_bytes = bytes(secret[1])
                json_data = data_bytes.decode('utf-8')
                log(f"Retrieved secret '{name}'")
                return json.loads(json_data)
            else:
                log(f"getSecret failed: code={code}, error={error_code}, msg={message}")
                return None
                
        except dbus.exceptions.DBusException as e:
            log(f"Retrieve error: {e}")
            return None
    
    def delete_secret(self, name: str) -> bool:
        """Delete a secret"""
        if not self.available:
            log("Secrets not available")
            return False
        
        try:
            # deleteSecret signature: (sss)(i)s
            result = self._call(
                'deleteSecret',
                '(sss)(i)s',
                (name, COLLECTION_NAME, self.plugin_name),
                (USER_INTERACTION_MODE,),
                ""
            )
            
            code = int(result[0])
            if code == 0:
                log(f"Deleted secret '{name}'")
                return True
            else:
                log(f"deleteSecret failed: code={code}")
                return False
                
        except dbus.exceptions.DBusException as e:
            log(f"Delete error: {e}")
            return False


# Global instance
_secrets = None

def get_secrets() -> SailfishSecrets:
    """Get the global secrets instance"""
    global _secrets
    if _secrets is None:
        _secrets = SailfishSecrets()
    return _secrets


# Convenience functions for user credentials

def save_user_credentials(server: str, school: str, username: str, secret: str) -> bool:
    """Save user credentials securely"""
    return get_secrets().store_secret(SECRET_USER_CREDS, {
        'server': server,
        'school': school,
        'username': username,
        'secret': secret
    })

def load_user_credentials() -> dict:
    """Load user credentials"""
    return get_secrets().retrieve_secret(SECRET_USER_CREDS)

def delete_user_credentials():
    """Delete user credentials"""
    return get_secrets().delete_secret(SECRET_USER_CREDS)


# Convenience functions for TRAP credentials

def save_trap_credentials(server: str, school: str, username: str, password: str) -> bool:
    """Save TRAP credentials securely"""
    return get_secrets().store_secret(SECRET_TRAP_CREDS, {
        'server': server,
        'school': school,
        'username': username,
        'password': password
    })

def load_trap_credentials() -> dict:
    """Load TRAP credentials - returns None if not configured"""
    return get_secrets().retrieve_secret(SECRET_TRAP_CREDS)

def delete_trap_credentials():
    """Delete TRAP credentials"""
    return get_secrets().delete_secret(SECRET_TRAP_CREDS)


def is_secrets_available() -> bool:
    """Check if Sailfish Secrets is available"""
    return get_secrets().available
