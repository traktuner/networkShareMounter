##### `⚠️ Warning for macOS 26.4: macOS 26.4 contains a bug that prevents mounting volumes outside of /Volumes! NSM versions 3.1.18 and 4.0.0 include a workaround when using macOS 26.4: The volume is mounted under /Volumes and a symbolic link is created in the target directory. ⚠️`

# <img src="networkShareMounter.png" width="45px"/> Network Share Mounter

Network Share Mounter connects SMB, AFP, and WebDAV shares automatically – at login, on network changes, without any manual interaction. With built-in Kerberos Ticket Management, authentication runs silently in the background. Configurable via MDM, enterprise-ready, and Open Source.

**[Visit our Network Share Mounter for more information and documentation](https://nsm.faumac.rrze.de)**.   

For the latest version, visit the [release page](https://gitlab.rrze.fau.de/faumac/networkShareMounter/-/releases).

**Key features**

- **Supports various protocols**: Easily mounts Windows (SMB/CIFS), AFP, and WebDAV shares.
- **Streamlined user experience:** Designed to be user-friendly for administrators and end users, eliminating the complexity associated with other methods such as scripts.
- **Fully configurability via MDM:** Distribute managed network shares and app-specific configurations via a configuration profile using Mobile Device Management (MDM) solutions.
- **User-Friendly menu bar interface:** Users can effortlessly add additional shares through the menu bar, providing flexibility beyond the managed ones.
- **Background mounting:** Shares are automatically mounted in the background based on network accessibility, requiring no user intervention.
- **Silent failure handling:** In the event of a mount failure, such as an unreachable share, no intrusive graphical user interface appears, ensuring a seamless user experience. Depending on the configuration, the Network Share Mounter icon in the menu bar adapts to provide a quick visual indicator of the current status.
- **Kerberos ticket management:** Serves as a potential alternative to Apple Enterprise Connect, Jamf Connect or NoMAD.
- **Kerberos and keychain integration:** In a Kerberos environment, there is no need to add user credentials for mounts, enhancing both: security and efficiency. Alternatively, user credentials can be securely stored in the user’s keychain.
- **Trigger via Apple Shortcuts and UNIX signals:** Mounting or unmounting configured shares can be triggered via UNIX signals or Apple Shortcuts.
- **Using Sparkle for auto-update:** With [Sparkle](https://sparkle-project.org/), the Network Share Mounter can update itself. In enterprise environments, this is not always desired, so automatic updates can be disabled.

## ✉️ Contact

For ideas, feature requests or bug reports, please reach out to us at the following address: [rrze-nsm-app@fau.de](mailto:rrze-nsm-app@fau.de).    
For general questions, you can contact [rrze-mac@fau.de](mailto:rrze-mac@fau.de).

`Developed with ❤️ by your FAUmac team`
