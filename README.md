# <img src="networkShareMounter.png" alt="drawing" width="90px"/> Network Share Mounter

In a university or corporate environment, it is often necessary to mount specific network shares based on departments or locations. Unfortunately, the built-in method for mounting shares in macOS is not very user-friendly and does not provide an ideal solution for enterprise environments. Solutions that rely on scripts or other tools are often too static and inflexible for end users.    

To create an optimal solution for both administrators and end users, we have developed the Network Share Mounter.    

The Network Share Mounter is designed as a single application for mounting a list of network shares. Ideally, this list is distributed as a configuration profile through an MDM solution based on workgroups, departments, project groups, etc. If a user needs to add additional shares beyond the managed ones, they can easily do so via the menu bar.     

Shares are mounted in the background based on network accessibility, requiring no user interaction. To enhance this process, we recommend using a Kerberos environment to eliminate the need for authentication during mounting. With version 3, user credentials can also be securely stored in the user's keychain for both managed and manually added shares. Additionally, version 3.1.0 supports the management of Kerberos tickets. Similar to Apple Enterprise Connect, Jamf Connect or NoMAD, Network Share Mounter handles the login and renewal of tickets in a Kerberos realm.

_For the latest version, as well as information on new features and bug fixes, go to the [release page](https://gitlab.rrze.fau.de/faumac/networkShareMounter/-/releases)._

**Key features**

- **Supports various protocols:** Easly mount Windows (SMB/CIFS), AFP and WebDAV Shares
- **Streamlined user experience:** Designed to be user-friendly for administrators and end-users, eliminating the complexity associated with other methods like scripts.
- **Fully configurability via MDM:** Distribute a list of managed network shares and configuration as a configuration profile using Mobile Device Management (MDM) solutions.
- **User-Friendly menu bar interface:** Users can effortlessly add additional shares through the menu bar, providing flexibility beyond the managed ones.
- **Background mounting:** Shares are automatically mounted in the background based on network accessibility, requiring no user intervention.
- **Silent failure handling:** In the event of a mount failure, such as an unreachable share, no intrusive graphical user interface will appear, ensuring a seamless user experience. Depending on the configuration, the Network Share Mounter icon in the menu bar will adapt to provide a quick visual indicator of the current status.
- **Kerberos ticket management:** Serves as a potential alternative to Apple Enterprise Connect, Jamf Connect or NoMAD.
- **Kerberos and keychain integration:** A Kerberos environment removes the need to add user credentials for mounts, enhancing both security and efficiency. Alternatively, user credentials can be securely stored in the user's keychain.
- **trigger by UNIX signals:** A mount/unmount of the configured shares can be triggered via Unix signals:
   - `kill -SIGUSR1 PID` triggers *unmount* of configured shares
   - `kill -SIGUSR2 PID` triggers *mount* of configured shares
   - (where `PID` is Network Share Mounter's process id)
- **Using Sparkle for auto-update:** With [Sparkle](https://sparkle-project.org/), the Network Share Mounter can update itself. In enterprise environments, this is not always desired, so the automatic update can, of course, be disabled.
- **Highly configurable:** Especially in the enterprise environment, it is desirable to customize certain features and behaviors to meet specific requirements.

<img src="Network%20Share%20Mounter%20-%20Screenshot.png" />  

## ⚙️ Configuration

Network shares are stored in a NSUserdefaults domain among other configurable aspects of the app. The easiest way to configure the app is to create a configuration profile and distribute the profile via MDM. Alternatively, the configuration can also be done manually via the command line (i.g. defaults). See [configuration preferences](#configuration-preferences) for all available values. 

**Username variable**   
To avoid creating an MDM distributed profile for each user, you can use `%USERNAME%`, which will be replaced with the current user's login name.

**SMBHome**  
If the current user has the `SMBHome` attribute defined via LDAP or Active Directory, their home directory will be mounted automatically. This typically occurs when the Mac is bound to an Active Directory and the LDAP attribute `HomeDirectory` is set. If necessary, one can manually set the attribute for a local user with the following command: `dscl . create /Users/<yourusername> SMBHome \home.your.domain<yourusername>`.

### Configuration preferences

For an easier configuration of all the preference keys without creating or modifying a custom configuration profile in XML format we have provided a [JSON Manifest Schema for Jamf Pro (Download)](https://gitlab.rrze.fau.de/faumac/networkShareMounter/-/blob/dev/jamf-manifests/Network%20Share%20Mounter.json) and a manifest for the [iMazing Profile Editor](https://imazing.com/profile-editor). 

 The defaults domain is `de.fau.rrze.NetworkShareMounter`. Available keys: 

| Key                 | Type  | Description            | Default value | Aviable with version | Required? | Example |
| :------------------ | :---- | :---------------------|:-------------------------------------- | --------------------------------- | ------- | ---- |
| `managedNetworkShares` | Array of dict | Array with all network shares. <br />You can configure the authentication type and mount for each share: <br /><br />**networkShare**: Server and share name (SMB, AFP, HTTPS)<br /><br />**authType**: *Authentication type for the share, it can be either through Kerberos (krb) or password (password):* <br />**username**: *Predefine a username for authentication using username/password*<br /><br />**mountPoint**: *Change the mount point name for the network share. <br />[Only applicable when location is not /Volumes](#5-why-is-it-not-possible-to-change-the-mount-point-name-when-using-volumes-for-the-mount-location)!  <br />Leave blank for the default value (recommended)*<br /><br />----<br />*Note: `%USERNAME%` will be replaced with the login name of the current user*. | - | ≥ 3.0.0 | - |managedNetworkShares = {<br/>  {<br/>  networkShare = "smb://filer.your.domain/share",<br/>  authType = "krb"<br/>  },<br/>  {<br/>  networkShare = "smb://home.your.domain/%USERNAME%",<br/>  authType = "krb"<br/>  },<br/>  {<br/>  networkShare = "smb://filer3.your.domain/share2",<br/>  authType = "password",<br/>  username =  "%USERNAME%"<br/>  }|
| `networkShares`            | Array   | Array with all (SMB) network shares.    <br />Note: `%USERNAME%` will be replaced with the login name of the current user.<br /><br>**⚠️ Deprecated with version 3**. <br />*Still available for v3 adaption* | -             | < 3.1.0         | -         | `smb://filer.your.domain/share`<br />`smb://homefiler.your.domain/%USERNAME%` |
| `autostart` | Boolean | If true, the app will be launched upon user login. | false | ≥ 2.0.0 | optional ||
| `canQuit` | Boolean | If true, the user can exit the app in the menu bar. | true | ≥ 2.0.0 | optional ||
| `canChangeAutostart` | Boolean | If set to false, the user can not change the autostart option. | true | ≥ 2.0.0 | optional ||
| `unmountOnExit` | Boolean | If set to false, the shares will be mounted after quitting the app. | true | ≥ 2.0.0 | optional ||
| `location` | String | Path where network shares will be mounted. <br />Make sure, that the user has read and write access to the mount location if the location is not `/Volumes`.<br />Leave blank for the default value *(highly recommended)* | - | ≥ 2.1.0 | optional | `/Volumes` |
| `cleanupLocationDirectory` | Boolean | 1) Directories named like the designated mount points for shares will be deleted, independently of the `cleanupLocationDirectory` flag.    <br /><br />2) Directories named like the shares with a "-1", "-2", "-3" and so on will also be deleted independently of the the flag.    <br /><br />3) If set to true, the mount location will be cleaned up from files defined in the `filesToDelete` array.   <br />*(The previous setting where too dangerous)* | false | ≥ 2.1.0 | - | `false` |
| `kerberosRealm` | String | Kerberos/AD Domain for user authentication. If set, automatic AD/Kerberos authentication and ticket renewal will be enabled | - | ≥ 3.0.0 | optional | `EXAMPLE.REALM.COM |
| `helpURL` | String | Configure a website link to help users interact with the application. | - | ≥ 2.0.0 | optional |https://www.anleitungen.rrze.fau.de/betriebssysteme/apple-macos-und-ios/macos/#networksharemounter|
| `enableAutoUpdater` | Boolean | Turns on the auto update framework so that the app can update itself | true | ≥ 3.0.4 | optional | |
| `usernameOverride` | String | Provides the option to change the username used for mounting directories (for example, a network home drive).<br/>This may be necessary if the local username does not match the one used for mounting.<br/>This value is usually configured locally on the Mac. | - | ≥ 3.1.0 | optional | `defaults write ~/Preferences/de.fau.rrze.NetworkShareMounter.plist usernameOverride -string "USERNAME"` |
| `showMountsInMenu` | Boolean | List (mounted/unmounted) shares directly in menu bar and open the mounted directories when they are clicked.<br/>WIf the value is set to `false`, the previously known menu will be displayed. | true | ≥ 3.1.0 | optional | |
| `menuAbout`<br/>`menuConnectShares`<br/>`menuDisconnectShares`<br/>`menuCheckUpdates`<br/>`menuShowSharesMountDir`<br/>`menuShowShares`<br/>`menuSettings`| String | This allows you to manage the individual menu items:<br/>Set to `hidden` to conceal the respective menu item, while `disabled` grays it out.<br/> If no values are set, the menu item is displayed normally. | - | ≥ 3.1.0 | optional | |

#### ⚠️ Important note for the `location` and `cleanupLocationDirectory` values

If the `location` value is left empty (or undefined), the directory (`~/Netzlaufwerk`) will be created as a subdirectory of the user's home, where the network shares will be mounted. Since this directory only contains mounted network shares, there is a routine to clean it up by deleting unnecessary files and directories.

If another directory is used to mount the network drives (like `location` = `/Volumes`) **it is strongly recommended** to disable the cleanup routine by setting `cleanupLocationDirectory` to `false`! 

Ensure that the user has both read and write access permissions to the mount location (the directory where the mounts are made) if you are not using predefined locations such as `~/Netzlaufwerk` or `~/Networkshares` in the user's home, or the `/Volumes` location, where the OS must handle the mount process.

*Previously, we announced a change to the default location (`useNewDefaultLocation`) to `/Volumes`. However, this will not be implemented due to issues with the mount process managed by the operating system. The default mount path will remain in the home directory.*

## 📚 FAQ
##### **1) Jamf recon stuck with configured Network Share Mounter app**  
This issue is likely due to the inventory collection configuration "Include home directory sizes" in Jamf Pro. Both versions of Network Share Mounter, v2 and legacy, mount the shares in the user's home directory (i.e., `~/Network shares`). If this option is enabled, Jamf Pro will attempt to collect the sizes of the network share mounts, causing the process to get stuck.

To resolve this behavior, go to **Settings > Computer Management - Management Framework > Inventory Collection** and disable the option "**Include home directory sizes**" in Jamf Pro, or modify the default mount path for the Network Share Mounter.

##### **2) Autostart**

There are several methods to enable autostart at login. For example, the Apple approach, as outlined in the Apple App Store guidelines. However, the app must be launched at least once. 
If you're using an MDM solution like *Jamf Pro*, you can create a policy to start the Network Share Mounter once per user and computer. Once this is done, your MDM will trigger the first run. After that, the app will open at every login. For example:

- Policy: `Autostart Network Share Mounter`
  - Trigger: `Login`
- - Frequency: `Once per user per computer`
  - Scope: `Network Share Mounter installed`
  - Policy content:
  - - Run Unix command: `sudo -u $(/usr/bin/stat -f%Su /dev/console) open -a /Applications/Network\ Share\ Mounter.app`

##### **3) Managed Login Itmes with macOS Ventura**

With macOS Ventura, Apple has introduced a feature that displays apps running in the background. Users can enable or disable these specific apps. To prevent the Network Share Mounter from being disabled at startup, you can add a [managed login item](https://support.apple.com/guide/deployment/managed-login-items-payload-settings-dep07b92494/web) payload to the Network Share Mounter configuration profile or create a separate profile containing the necessary values. For example:

* Rule Type: `Bundle Identifier`
* Rule Value: `de.fau.rrze.NetworkShareMounter`
* Rule Comment: `Prevent disabling the Network Share Mounter autostart`

##### **4) How can I log the Network Share Mounter for debugging?**

With version 3, logging has significantly improved. You can use either Konsole.app or the terminal with the following command to log the app:

``log stream --predicate "subsystem == 'de.fau.rrze.NetworkShareMounter'" --level debug``

##### **5) Why is it not possible to change the mount point name when using /Volumes for the mount location?**

When mounting shares in `/Volumes`, the operating system manages the entire mount process and does not permit programmatic changes to the mount point name. Therefore, it is not possible to change the name. If the key `mountPoint` is configured, it will be ignored when using `/Volumes` as the mount location.

##### **6) Is there a way to centrally control the collection of crash reports via MDM?**

Network Share Mountre is now using a tool to collect issues and crash reports. It has become apparent that there are recurring errors that we cannot reproduce. Debugging such problems is often time-consuming. Therefore, we decided to look for a tool that collects as few data as possible, is open source, and can be hosted locally in our data center. We chose [Sentry](https://sentry.io).
- We use a *locally hosted* instance of Sentry, not one hosted in the cloud. The data therefore *never leaves our local servers*, hosted in our own data center.
- Since we have no interest in any user data, *we only collect data that aids us in debugging*.
- We have introduced a new switch that turns off the collection and sending of analysis data. **This switch cannot be configured via MDM because we believe every user should decide for themselves whether to support us with their crash reports.**

## 🚀 Planned features and releases

* ~Change default mount location to `/Volumes~ *(cancelled)*
* Remove the legacy  `networkShares`  value *(ETA Winter 2025, v3.2)*

## ✉️ Contact

For ideas, enhancements, or bug reports, please reach out to us at the following address: [rrze-nsm-app@fau.de](mailto:rrze-nsm-app@fau.de).    
For general questions, you can contact the team directly at [rrze-mac@fau.de](mailto:rrze-mac@fau.de).

`Developed with ❤️ by your FAUmac team`
