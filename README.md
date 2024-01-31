# <img src="networkShareMounter.png" alt="drawing" width="90px"/> Network Share Mounter 

In a university or corporate environment, it is usually necessary to mount specific network shares depending on departments or locations. Unfortunately, the built-in method of macOS for mounting shares is not very user-friendly and also does not provide an ideal solution for enterprise environments. Solutions based on scripts or other tools are often to static and inflexible for end users. 
To create a perfect solution for administrators _and_ end users, we have developed the Network Share Mounter.

The concept behind the Network Share Mounter is to have a single application for mounting a list of network shares. Ideally, the list of shares is distributed as a configuration profile with an MDM solution based on workgroups, departments, project groups, etc. If a user needs to add additional shares beyond the managed ones, they can easily add them via the menu bar.
The Shares are mounted in the background based on network accessibility without requiring any user interaction. To enhance this process, a Kerberos environment is recommended to avoid the need for authentication during a mount. With version 3, user credentials can also be stored securely in the user's keychain (managed and manually added shares).

**Key features**

- **Supports various protocols:** Easly mount Windows (SMB/CIFS), AFP and WebDAV Shares
- **Streamlined user experience:** Designed to be user-friendly for administrators and end-users, eliminating the complexity associated with other methods like scripts.
- **Fully configurability via MDM:** Distribute a list of managed network shares and configuration as a configuration profile using Mobile Device Management (MDM) solutions.
- **User-Friendly menu bar interface:** Users can effortlessly add additional shares through the menu bar, providing flexibility beyond the managed ones.
- **Background mounting:** Shares are automatically mounted in the background based on network accessibility, requiring no user intervention.
- **Silent failure handling:** In the event of a mount failure (e.g., unreachable share), no intrusive graphical user interface will appear, ensuring a seamless user experience. Depending on the configuration, the Network Share Mounter icon in the menu bar adapts to provide a quick visual indicator of the current status.
- **Kerberos and keychain integration:** A Kerberos environment eliminates the need for adding user credentials for mounts, enhancing both security and efficiency. Alternatively, user credentials can be securely stored in the user's keychain.

<img src="Network%20Share%20Mounter%20-%20Screenshot.png" />  

## ⚙️ Configuration

Network shares are stored in a NSUserdefaults domain among other configurable aspects of the app. The easiest way to configure the app is to create a configuration profile and distribute the profile via MDM. Alternatively, the configuration can also be done manually via the command line (i.g. defaults). See [configuration preferences](#configuration-preferences) for all available values. 

**Username variable**
To avoid creating a profile for every user you can use `%USERNAME%`, which will be replaced with the login name of the current user. 

**SMBHome**  
If the current user has the attribute `SMBHome` defined via LDAP or Active Directory, the user home will be mounted automatically. This is usually the case when the Mac is bound to an Active Directory and the LDAP attribute `HomeDirectory` is set. If necessery, you can set the attribute for a local user manuelly: `dscl . create /Users/<yourusername> SMBHome \home.your.domain<yourusername>`.

### Configuration preferences

For an easier configuration of all the preference keys without creating or modifying a custom configuration profile in XML format we have provided a [JSON Manifest Schema for Jamf Pro (Download)](https://gitlab.rrze.fau.de/faumac/networkShareMounter/-/blob/dev/jamf-manifests/Network%20Share%20Mounter.json) and a manifest for the [iMazing Profile Editor](https://imazing.com/profile-editor). 

 The defaults domain is `de.fau.rrze.NetworkShareMounter`. Available keys: 

| Key                 | Type  | Description            | Default value | Aviable with version | Required? | Example |
| :------------------ | :---- | :---------------------|:-------------------------------------- | --------------------------------- | ------- | ---- |
| `managedNetworkShares` | Array of dict | Array with all network shares. <br />You can configure the authentication type and mount for each share: <br /><br />**networkShare**: Server and share name (SMB, AFP, HTTPS)<br /><br />**authType**: *Authentication type for the share, it can be either through Kerberos (krb) or password (password):* <br /><br />**username**: *Predefine a username for authentication using username/password*<br /><br />**mountPoint**: *Change the mount point name for the network share. Leave blank for the default value (recommended)*<br /><br />*Note: `%USERNAME%` will be replaced with the login name of the current user*. | - | ≥ 3.0.0 | - |managedNetworkShares = {<br/>  {<br/>  networkShare = "smb://filer.your.domain/share",<br/>  authType = "krb"<br/>  },<br/>  {<br/>  networkShare = "smb://home.your.domain/%USERNAME%",<br/>  authType = "krb"<br/>  },<br/>  {<br/>  networkShare = "smb://filer3.your.domain/share2",<br/>  authType = "password",<br/>  username =  "%USERNAME%"<br/>  }|
| `networkShares`            | Array   | Array with all (SMB) network shares.    <br />Note: `%USERNAME%` will be replaced with the login name of the current user.<br /><br>**⚠️ Deprecated with version 3**. <br />*Still available for v3 adaption* | -             | < 3.1.0         | -         | `smb://filer.your.domain/share`<br />`smb://homefiler.your.domain/%USERNAME%` |
| `autostart` | Boolean | If true, the app will be launched upon user login. | false | ≥ 2.0.0 | optional ||
| `canQuit` | Boolean | If true, the user can exit the app in the menu bar. | true | ≥ 2.0.0 | optional ||
| `canChangeAutostart` | Boolean | If set to false, the user can not change the autostart option. | true | ≥ 2.0.0 | optional ||
| `unmountOnExit` | Boolean | If set to false, the shares will be mounted after quitting the app. | true | ≥ 2.0.0 | optional ||
| `location` | String | Path where network shares will be mounted. <br />Leave blank for the default value *(highly recommended)* | - | ≥ 2.1.0 | optional | `/Volumes` |
| `useNewDefaultLocation` | Boolean | Use the new default mount location (`/Volumes`)<br /><br />**⚠️ With version 3 the old default mount path (~/Netzlaufwerke/) is deprecated.** | false | 3.0.0 | optional |  |
| `cleanupLocationDirectory` | Boolean | 1) Directories named like the designated mount points for shares will be deleted, independently of the `cleanupLocationDirectory` flag.    <br /><br />2) Directories named like the shares with a "-1", "-2", "-3" and so on will also be deleted independently of the the flag.    <br /><br />3) If set to true, the mount location will be cleaned up from files defined in the `filesToDelete` array.   <br />*(The previous setting where too dangerous)* | false | ≥ 2.1.0 | - | `false` |
| `kerberosRealm` | String | Kerberos/AD Domain for user authentication. If set, automatic AD/Kerberos authentication and ticket renewal will be enabled | - | ≥ 3.0.0 | optional | EXAMPLE.REALM.COM |
| `helpURL` | String | Configure a website link to help users interact with the application. | - | ≥ 2.0.0 | optional |https://www.anleitungen.rrze.fau.de/betriebssysteme/apple-macos-und-ios/macos/#networksharemounter|

#### ⚠️ Important note for the `location`,  `cleanupLocationDirectory` and `useNewDefaultLocation` values

If the value `location` left empty (or undefined), the directory (`~/Netzlaufwerk`) will be created as a subdirectory of the user's home where the network shares will be mounted. Since this directory always contains only mounted network shares, there is a routine to clean up this directory and deletes unnecessary files and directories.    
If another directory is used to mount the network drives (like `location` = `/Volumes`) **it is strongly recommended** to disable the cleanup routine by setting `cleanupLocationDirectory` to `false` !

**Also, in a feature release, the new default location will be set to `/Volumes`**. The `useNewDefaultLocation` parameter allows users to adopt this default value ahead of the official release. This option is provided to ease the transition for administrators.

## 📚 FAQ
##### **1) Jamf recon stuck with configured Network Share Mounter app**  
This is probably due the inventory collection configuration "Include home directory sizes" in Jamf Pro. Both Network Share Mounter versions, v2 and legacy, mounting the shares in the users home (i.g. `~/Network shares`). If the option is now enabled, Jamf Pro will also try to collect the size of the network share mounter mounts and the process gets stuck.

To resolve this behaviour, go to **Settings > Computer Management - Management Framework > Inventory Collection** and disable the option "**Include home directory sizes**" in Jamf Pro or modify the Network Share Mounter default mount path. 

##### 2) Autostart 

There are several methods to accomplish the autostart at login. For example, the Apple way, as it is also defined in the Apple App Store guideline. **But the app *has* to be started at least once**.  
If you're using a MDM solution like *Jamf Pro* you can create a policy to start the Network Share Mounter _once per user and computer_. If done, your MDM trigger the first run. After that, the app will open on every log-in. Example: 

- Policy: `Autostart Network Share Mounter`
  - Trigger: `Login`
- - Frequency: `Once per user per computer`
  - Scope: `Network Share Mounter installed`
  - Policy content:
  - - Run Unix command: `sudo -u $(/usr/bin/stat -f%Su /dev/console) open -a /Applications/Network\ Share\ Mounter.app`

##### **3) Managed Login Itmes with macOS Ventura**

With macOS Ventura, Apple has added a feature to show apps which are starting and working in the background. Users also have the posibillity to enable or disable these specific apps. To prevent disabling the Network share Mounter autostart you can add a [managed login item](https://support.apple.com/guide/deployment/managed-login-items-payload-settings-dep07b92494/web) payload to the Network Share Mounter configuration profile or create a seperate profile containing the necessery values. Example:

* Rule Type: `Bundle Identifier`
* Rule Value: `de.fau.rrze.NetworkShareMounter`
* Rule Comment: `Prevent disabling the Network Share Mounter autostart`

##### **4) How can I log the Network Share Mounter for debugging?**

With version 3, logging has been significantly improved. You can use either the Konsole.app or the terminal with the following command to log the app:

``log stream --predicate "subsystem == 'de.fau.rrze.NetworkShareMounter'" --level debug``

## 🚀 Planned features and releases

* Kerberos/AD handling for user authentication like Apple Enterprise Connect, Jamf Connect or NoMAD *(Beta in v3.0, Release ETA Summer 2024, v3.1)*
* Change default mount location to `/Volumes` *(ETA Summer 2024, v3.1)*
* Remove the legacy  `networkShares`  value *(ETA Summer 2024, v3.1)*

## ✉️ Contact

For ideas, enhancements, or bug reports, please contact us through the following address: [rrze-nsm-app@fau.de](mailto:rrze-nsm-app@fau.de).    
For general questions, you can contact the team at [rrze-mac@fau.de](mailto:rrze-mac@fau.de) directly.

`Developed with ❤️ by your FAUmac team`
