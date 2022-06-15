# <img src="networkShareMounter.png" alt="drawing" width="90px"/> networkShareMounter

In a university, there is a requirement that departments have specific SMB shares on their own network that users should mount. In the same way, in a company - depending on the department or location - there could also be different shares that are to be used. The idea behind the networkShareMounter is that there is a single application that takes care of mounting a list of network shares in an enterprise or university environment. Such a list of shares will be ideally distributed as configuration profiles with an MDM based on workgroups, departments, project-groups etc.

Based on the network accessibility, the shares are mounted in the background without any user interaction. Even if a mount fails (e.g. if the share is unreachable), no GUI will be displayed. A Kerberos environment is therefore recommended so that no authentication is required for a mount. Alternatively, the user credentials can also be stored in the user's keychain by manually mounting a share once. So please note that no notification will be displayed if the credantials are invalid or unavailable!  

**Configuration**  
Network shares are stored in a NSUserdefaults domain among other configurable aspects of the app. The easiest way to do this is to create a configuration profile and distribute is via MDM. Alternatively, the configuration can also be done manually via the command line. As a tip: to avoid creating a profile for every user, use %USERNAME% which will be replaced with the login name of the current user. See [configuration preferences](#configuration-preferences) in v2 for all available values. 

**SMBHome**  
If the current user has the attribute `SMBHome` defined via LDAP or Active Directory, the user home will also be mounted automatically. This is usually the case when the Mac is bound to an Active Directory and the LDAP attribute `HomeDirectory` is set. You can also set it for a local user if you want: `dscl . create /Users/<yourusername> SMBHome \home.your.domain<yourusername>`.

**v2 and Legacy?**  
Staring with December 2021 there are two different versions of the app: The [background LaunchAgent comamnd line application](#networksharemounter-legacy-the-command-line-app) legacy app (not under active development anymore) and a [menu bar based app](#network-share-mounter-v2) with more configuration options and features for end users. 

## Network Share Mounter (v2)
The *Network Share Mounter* app is loosely based on the code of the command line version. It lives in the user's menu bar and is more visible and manageable for the user, as it has the possibility to add some (additional personal) shares to be mounted or the user can decide if the app will be automatically started on login. 

### Configuration preferences
For an easier configuration of all the preference keys without creating or modifying a custom Configuration Profile in XML format we provieded a JSON Manifest Schema for Jamf Pro. [Download the manifest file](https://gitlab.rrze.fau.de/faumac/networkShareMounter/-/blob/master/jamf-manifests/Network%20Share%20Mounter.json). 

 The defaults domain for v2 is `de.fau.rrze.NetworkShareMounter`. List with all available values: 

| Key                 | Type  | Description            | Default Value | Aviable in version | Required? | Example |
| :------------------ | :---- | :---------------------|:-------------------------------------- | --------------------------------- | ------- | ---- |
| `networkShares`     | Array | array with all network shares. For example configured through a MDM | - | all | - |`smb://filer.your.domain/share`<br />`smb://homefiler.your.domain/%USERNAME%`|
| `customNetworkShares` | Array | array with all user configured network shares                | - | all | optional |`smb://myhomefiler.my.domain/share`|
| `autostart` | Boolean | if set, the app will be launched on user-login | false | v2 | optional ||
| `canQuit` | Boolean | if set, the user can quit the app | true | v2 | optional ||
| `canChangeAutostart` | Boolean | if set to false, the user can not change the Autostart option | true | v2 | optional ||
| `unmountOnExit` | Boolean | if set to false the shares will be mounted after quitting the app | true | v2 | optional ||
| `location` | String | This is the path under which the shares will be mounte  | - | v2 | optional | `/Volumes` |
| `cleanupLocationDirectory` | Boolean | if set to true the mount location will be cleaned up from obstructing files and directories. Use with caution! | false | v2 | - | `false` |
| `helpURL` | String | configure a help URL to help users interact with the application | - | v2 | optional |https://www.anleitungen.rrze.fau.de/betriebssysteme/apple-macos-und-ios/macos/#networksharemounter|  

If `location` is left empty (or is not defined), a directory is created in a subdirectory of the user's home where the network drives will be mounted. Since this directory always contains only mounted network shares, there is a routine that cleans up this directory and deletes unnecessary files and directories.    
If another directory is used to mount the network drives (like `location` set to, for example, `/Volumes`) **it is strongly recommended** to disable the cleanup routine by setting `cleanupLocationDirectory` to `false`.

### Screenshots
Screenshots of our Network Share Mounter app. On the left the menu bar icon with the mount, unmount and quit options. On the right the configuration window with the custom network share list:

<img src="networkShareMounterv2Screenshot.png" />  

----  

## networkShareMounter Legacy (the command line app)

The legacy networkShareMounter is started by a [LaunchAgent](https://gitlab.rrze.fau.de/faumac/networkShareMounter/-/blob/master/networkShareMounter/de.uni-erlangen.rrze.networkShareMounter.plist) at every network change (for automatic remounting) and when a user logs in. This process is done in the background, without any user interaction. 

### How to configure the command line app

The defaults domain for our [pre-built package](https://gitlab.rrze.fau.de/faumac/networkShareMounter/-/releases) is `de.uni-erlangen.rrze.networkShareMounter`. If you want to distribute the plist with a configuration profile you have to do it with the payload `com.apple.ManagedClient.preferences` like this:

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

[Download example Configuration Profile](https://gitlab.rrze.fau.de/faumac/networkShareMounter/-/blob/master/jamf-manifests/networkShareMounter%20Legacy.mobileconfig).

If you want to configure shares manually, you can use this command:

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

## FAQ
### 1) Jamf recon stuck with configured Network Share Mounter app
This is probably due the innventory collection configuration "Include home directory sizes" in Jamf (Pro). Both Network Share Mounter versions, v2 and legacy, mounting the shares in the users home (~/Network Shares). If the option is now enabled, Jamf will also try to collect the size of the network share mounter mounts and the process get stuck.

To resolve this behaviour, go to **Settings > Computer Management - Management Framework > Inventory Collection** and disable the option **Include home directory sizes**.

## Contact
Feel free to contact us for ideas, enhancements or bug reports at the [service desk address](mailto:rrze-gitlab+faumac-networksharemounter-506-issue-@fau.de).    
For general questions you can write directly to the team at [rrze-mac@fau.de](mailto:rrze-mac@fau.de).


`Developed with ❤️ by your FAUmac team`

