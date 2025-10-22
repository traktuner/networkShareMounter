# <img src="networkShareMounter.png" alt="Network Share Mounter logo" width="90px"/> Network Share Mounter

In a university or corporate environment, it is often necessary to mount specific network shares based on departments or locations. Unfortunately, the built-in method for mounting shares in macOS is not very user‑friendly and does not provide an ideal solution for enterprise environments. Solutions that rely on scripts or other tools are often too static and inflexible for end users.  

To create an optimal solution for both administrators and end users, we have developed the **Network Share Mounter**.

The Network Share Mounter is designed as a single application for mounting a list of network shares. Ideally, this list is distributed as a configuration profile through an MDM solution based on workgroups, departments, project groups, etc. If a user needs to add additional shares beyond the managed ones, they can easily do so via the menu bar.

Shares are mounted in the background based on network accessibility, requiring no user interaction. To enhance this process, we recommend using a Kerberos environment to eliminate the need for authentication during mounting. With version 3, user credentials can also be securely stored in the user's keychain for both managed and manually added shares. Additionally, version 3.1.0 supports the management of Kerberos tickets. Similar to Apple Enterprise Connect, Jamf Connect or NoMAD, Network Share Mounter handles the login and renewal of tickets in a Kerberos realm.

_For the latest version, as well as information on new features and bug fixes, go to the [release page](https://gitlab.rrze.fau.de/faumac/networkShareMounter/-/releases)._

## Table of Contents
- [Key Features](#key-features)
- [Configuration](#configuration)
- [FAQ](#faq)
- [Planned Features & Releases](#planned-features--releases)
- [Contact](#contact)

## Key features

- **Supports various protocols:** Easily mount Windows (SMB/CIFS), AFP and WebDAV shares.
- **Streamlined user experience:** Designed to be user‑friendly for administrators and end‑users, eliminating the complexity associated with scripts.
- **Fully configurable via MDM:** Distribute a list of managed network shares and configuration as a configuration profile using Mobile Device Management (MDM) solutions.
- **User‑friendly menu bar interface:** Users can effortlessly add additional shares through the menu bar, providing flexibility beyond the managed ones.
- **Background mounting:** Shares are automatically mounted in the background based on network accessibility, requiring no user intervention.
- **Silent failure handling:** In the event of a mount failure (e.g., an unreachable share), no intrusive graphical user interface will appear. The menu‑bar icon adapts to provide a quick visual indicator of the current status.
- **Kerberos ticket management:** Serves as a potential alternative to Apple Enterprise Connect, Jamf Connect or NoMAD.
- **Kerberos and keychain integration:** A Kerberos environment removes the need to add user credentials for mounts, enhancing both security and efficiency. Alternatively, user credentials can be securely stored in the user's keychain.
- **Trigger by UNIX signals:** A mount/unmount of the configured shares can be triggered via Unix signals:  
  - `kill -SIGUSR1 PID` → *unmount* of configured shares  
  - `kill -SIGUSR2 PID` → *mount* of configured shares  
  *(where `PID` is Network Share Mounter's process ID)*
- **Sparkle auto‑update:** With [Sparkle](https://sparkle-project.org/), the app can update itself. In enterprise environments this can be disabled.
- **Highly configurable:** Especially in the enterprise environment, it is desirable to customize certain features and behaviors to meet specific requirements.

<img src="Network%20Share%20Mounter%20-%20Screenshot.png" alt="Network Share Mounter screenshot" />

## ⚙️ Configuration

Network shares stored in a `NSUserDefaults` domain among other configurable aspects of the app. The easiest way to configure the app is to create a configuration profile and distribute it via MDM. Alternatively, the configuration can also be done manually via the command line (e.g., `defaults`). See **Configuration preferences** below for all available keys.

### Username variable
To avoid creating an MDM‑distributed profile for each user, you can use `%USERNAME%`, which will be replaced with the current user's login name.

### SMBHome
If the current user has the `SMBHome` attribute defined in Active Directory, their home directory will be mounted automatically. **This feature requires the Mac to be bound to an Active Directory domain.** The `SMBHome` attribute corresponds to the `HomeDirectory` field in AD.

**Requirements for automatic SMBHome mounting**
- Mac must be bound to Active Directory (`dsconfigad -show` to verify)
- Current user must be an AD user (not a local account)
- SMBHome attribute must be set in AD for the user

For local testing, you can manually set the SMBHome attribute for a local user:

