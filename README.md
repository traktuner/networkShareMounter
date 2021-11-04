# <img src="networkShareMounter.png" alt="drawing" width="80px"/> networkShareMounter

The networkShareMounter mounts network shares using a predefined plist. The easiest way to distribute them is to use configuration profiles with an MDM.

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

### Hints

- There is a `customNetworkShares` array in the same defaults domain, that can be used to add additional shares by the user. 
- If you want to change the installation directory, go to **Build Settings** > **Deployment** > **Installation Directory**. But keep in mind that you also have to change the path of the LaunchAgent. 
- If you don't want to use a configuration profile to distribute the array of shares, this command could be interesting for: 

```sh
defaults write <your defaultsdomain> networkShares -array "smb://filer.your.domain/share" "smb://filer2.your.domain/home/Another Share/foobar" "smb://home.your.domain/%USERNAME%"
```

## Optional Paramater
There is an optional parameter `--openMountDir` which opens a new finder window with the directory and the mounted shares
