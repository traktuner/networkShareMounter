# <img src="networkShareMounter.png" alt="drawing" width="90px"/> networkShareMounter

The networkShareMounter mounts network shares using a predefined plist. The easiest way to distribute them is to use configuration profiles with an MDM. The idea behind this app was to create a method for a workgroup, a department, a project-group etc. to mount a predefined bunch of (smb) network shares. Via MDM the list can be distributed to the specific group of Macs (or users). 

Starting with december 2021 there are two "versions" of the app, one background LaunchAgent comamnd line application and a menu based app bundle

## networkShareMounter (the command line app)

The networkShareMounter is started by a LaunchAgent at every network change (for automatic remounting) and when a user logs in. This is done in the background, without any user interaction.

Even if the mount fails (e.g. if the Mac is in a remote location without connection to your file servers), no gui will be displayed and your users are not distracted. 

We recommend the use of Kerberos tickets or mount the shares once manually to store the password in the keychain. 

Network shares are fetched from a configurable NSUserDefaults domain - the easiest way to do this is to use an MDM to distribute a configuration profile (what we recommend) or execute a script. Here you may use `%USERNAME%`which will be replaced with the username of the current user. 

If the current user has the attribute `SMBHome`, the user home will also be mounted. This is usually the case when the Mac is bound to an Active Directory and the LDAP attribute `HomeDirectory` is set. You can also set it for the local user if you want: `dscl . create /Users/<yourusername> SMBHome \home.your.domain<yourusername>`

If you want to distribute the plist with a configuration profile you have to do it with a payload `com.apple.ManagedClient.preferences` like this:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>networkShares</key>
	<array>
		<string>smb://home.your.domain/%USERNAME%</string>
		<string>smb://filer1.your.domain/share</string>
		<string>smb://filer2.your.domain/another share/foobar</string>
	</array>
</dict>
</plist>
```

### Optional Paramater
There is an optional parameter `--openMountDir` which opens a new finder window with the directory and the mounted shares

## Network Share Mounter (the app bundle)

The *Network Share Mounter* app is based on the code of the command-line version. It lives in the user's menu bar and is more visible and manageable for the user, as he has the possibility to add some (additional personal) shares to be mounted and decide if the app will be started on login.   
Most of the settings mentioned for the command line app version are valid for the app bunlde.

## Configuration

- There is a `customNetworkShares` (both versions) array in the same defaults domain, that can be used to add additional shares by the user. 
- If you want to change the installation directory, go to **Build Settings** > **Deployment** > **Installation Directory**. But keep in mind that you also have to change the path of the LaunchAgent (command line version). 
- The full App version (*Network Share Mounter*) has a few additional attributes:
   - `autostart`(default: `false`): if set, the app will be launched on user-login
   - `canQuit`(default: `true`): if set, the user can quit the app
   - `canChangeAutostart`: if set to false, the user can not change the Autostart option
- If you don't want to use a configuration profile to distribute the array of shares, this command could be used to configure the app for "personal" use: 

```sh
defaults write <your defaultsdomain> networkShares -array "smb://filer.your.domain/share" "smb://filer2.your.domain/home/Another Share/foobar" "smb://home.your.domain/%USERNAME%"
```

