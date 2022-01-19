# <img src="networkShareMounter.png" alt="drawing" width="90px"/> networkShareMounter

The networkShareMounter mounts network shares using a predefined plist. The easiest way to distribute them is to use configuration profiles with an MDM. The idea behind this app is to create a method to mount a bunch of predefined (SMB) network shares for a workgroup, department, project-group etc. For example, the configuration can be distributed to a specific group of Macs (or users) via an MDM.

The shares are mounted in the background without any user interaction. Even if the mount fails (e.g. if the Mac is another location without connection to the configured servers), no GUI will be displayed and your users are not distracted. 
Because of this we recommend the use of Kerberos tickets or mount the shares once manually to store the password in the users macOS keychain. So please note, no notification will be displayed if the credantials are wrong or not avaible!  

**Configuration**

Network shares are fetched from a configurable NSUserDefaults domain - the easiest way to do this is to use an MDM to distribute a configuration profile (what we recommend) or execute a script. Here you may use `%USERNAME%`which will be replaced with the username of the current user. See [configuration preferences]() in v2 for all avaible values. 

**SMBHome**

If the current user has the attribute `SMBHome`, the user home will also be mounted. This is usually the case when the Mac is bound to an Active Directory and the LDAP attribute `HomeDirectory` is set. You can also set it for the local user if you want: `dscl . create /Users/<yourusername> SMBHome \home.your.domain<yourusername>`

**v2 and Legacy?**

Since December 2021 there are two different versions of the app: The [background LaunchAgent comamnd line application]() which is legacy and a [menu bar based app]() with more configuration options for end users. 

## Network Share Mounter (v2)
The *Network Share Mounter* app is based on the code of the command line version. It lives in the user's menu bar and is more visible and manageable for the user, as he has the possibility to add some (additional personal) shares to be mounted and decide if the app will be started on login.   



### Configuration preferences
To help administartor to configure the Network Share Mounter we provied a Jamf Custom Schema for configuration profiles. Description of all avaible values: 

| Key                 | Type  | Description            | Default Value | Aviable in version | Required? | Example |
| :------------------ | :---- | :---------------------|:-------------------------------------- | --------------------------------- | ------- | ---- |
| `networkShares`     | Array | array with all network shares. For example configured through a MDM | - | all | - |`smb://filer.your.domain/share`<br />`smb://homefiler.your.domain/%USERNAME%`|
| `customNetworkShares` | Array | array with all user configured network shares                | - | all | optional |`smb://myhomefiler.my.domain/share`|
| `autostart` | Boolean | if set, the app will be launched on user-login | false | v2 | optional ||
| `canQuit` | Boolean | if set, the user can quit the app | true | v2 | optional ||
| `canChangeAutostart` | Boolean | if set to false, the user can not change the Autostart option | true | v2 | optional ||
| `unmountOnExit` | Boolean | if set to false the shares will be mounted after quitting the app | true | v2 | optional ||
| `helpURL` | String | configure a help URL to help users interact with the application | - | v2 | optional |https://www.anleitungen.rrze.fau.de/betriebssysteme/apple-macos-und-ios/macos/#networksharemounter|

## networkShareMounter Legacy (the command line app)

The legacy networkShareMounter is started by a [LaunchAgent](https://gitlab.rrze.fau.de/faumac/networkShareMounter/-/blob/master/networkShareMounter/de.uni-erlangen.rrze.networkShareMounter.plist) at every network change (for automatic remounting) and when a user logs in. This process is done in the background, without any user interaction. 

### How to configure the command line app

The defaults domain for your [pre-built package](https://gitlab.rrze.fau.de/faumac/networkShareMounter/-/releases) is `de.uni-erlangen.rrze.networkShareMounter`. If you want to distribute the plist with a configuration profile you have to do it with the payload `com.apple.ManagedClient.preferences` like this:

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

Download an example configuration profile here: <example_link_here> 

If you want to configure shares manuelly, you can use this command:

```bash
defaults write de.uni-erlangen.rrze.networkShareMounter networkShares -array "smb://filer.your.domain/share" "smb://filer2.your.domain/home/Another Share/foobar" "smb://home.your.domain/%USERNAME%"
```

```bash
defaults write de.uni-erlangen.rrze.networkShareMounter customNetworkShares -array "smb://private.filer.home/share"
```

### Optional paramater and options

* With the optional array  `customNetworkShares`  users can add own network shares to the configuration. See manually confiugration above for detauls.
* There is an optional parameter `--openMountDir` which opens a new finder window of the networkShareMounter mount directory. (e.g. "\~/Network shares" or "\~/Netzlaufwerke")
* If you want to change the installation directory, go to **Build Settings** > **Deployment** > **Installation Directory**. But keep in mind that you also have to change the path of the LaunchAgent (command line version). 
