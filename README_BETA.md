# Network Share Mounter 4.0 - Beta

Network Share Mounter automatically mounts network shares (SMB/CIFS, AFP, WebDAV) on macOS, designed for enterprise environments with MDM support and user-managed configurations.

## What's New in Version 4

### Modern SwiftUI Interface

Version 4 features a completely redesigned user interface built with SwiftUI:
- Clean, modern settings window with tabbed navigation
- Better organization of shares and authentication profiles
- Native macOS design for seamless system integration

### Authentication Profiles - Reusable Credentials

**Major new feature:** Instead of storing credentials separately for each share, you can now create reusable authentication profiles.

#### How It Works

Create an authentication profile once with your username and password (or Kerberos settings), then use it across multiple shares. When you need to update your password, change it in one place and all associated shares are automatically updated.

#### Benefits

- **Fewer duplicates**: Credentials stored once in Keychain instead of multiple times
- **Easier management**: Update passwords centrally, not per-share
- **Clear overview**: See which shares use which profiles
- **Flexible**: Reassign shares to different profiles anytime

#### Profile Types

**Kerberos Profiles**
- For Active Directory environments
- Automatic ticket management
- No password storage needed
- Single Sign-On support

**Password Profiles**
- Username + password stored securely in macOS Keychain
- For local servers or non-AD environments
- Multiple profiles for different credentials

#### Automatic Profile Assignment

When adding new shares, Network Share Mounter automatically tries to assign a matching profile:
- **Kerberos shares**: Matched by realm and username
- **Password shares**: Intelligent matching by username (supports UPN format)
- Manual assignment always available if needed

### Custom Mount Point Names

**New in Version 4:** You can now choose custom local names for your network shares, solving the duplicate share name problem.

#### The Problem (Solved)

Previously, mounting shares with identical names from different servers would cause conflicts:
```
smb://europe.domain.com/accounting → ~/Networkshares/accounting
smb://usa.domain.com/accounting → Conflict! Could not mount second share
```

#### The Solution

Now you can assign individual local names to each share:
```
smb://europe.domain.com/accounting → ~/Networkshares/accounting-europe
smb://usa.domain.com/accounting → ~/Networkshares/accounting-usa
```

Or use descriptive names:
```
smb://fileserver/projects → ~/Networkshares/Work-Projects
smb://backup-server/data → ~/Networkshares/Backup-Data
```

#### How It Works

1. **Auto-generated names**: When adding a share, the name is automatically extracted from the URL
2. **Fully customizable**: Change the name to anything you want (e.g., "Project Files", "Backup Server")
3. **Duplicate detection**: Network Share Mounter automatically checks for name conflicts
4. **Live validation**: Get instant feedback if a name is already in use or contains invalid characters

#### Important Note: Finder Display

**In the file system:**
- Shares are mounted with your chosen name
- Applications and scripts see the correct path
- Terminal shows your custom names

**In Finder:**
- ⚠️ **Finder displays the original share name from the server**
- This is a macOS system limitation for SMB mounts
- The actual mount point path is still correct and usable

**Example:**
```
Your configuration: "MyBackup" for smb://nas.local/backup
File system path:   ~/Networkshares/MyBackup ✅
Finder shows:       "backup" (from server) ⚠️
```

This limitation does not affect functionality - applications, scripts, and the Terminal all work with your chosen name. Only the Finder sidebar shows the server's share name.

#### Character Restrictions

Allowed:
- ✅ Letters, numbers, spaces
- ✅ Hyphens, underscores, parentheses
- ✅ Umlauts and Unicode characters (ä, ö, ü, café, etc.)

Not allowed:
- ❌ Forward slash `/` (path separator)
- ❌ Newlines, control characters
- ❌ More than 200 characters

### Additional Improvements

- **Native autostart**: Uses macOS 13+ `SMAppService` API instead of using an external library
- **Better error messages**: Clear, actionable error descriptions
- **Modern Swift architecture**: Full async/await and Actor implementation
- **Comprehensive testing**: Unit tests for critical components

## System Requirements

- **macOS 13.5 (Ventura) or later**
- Optional: Kerberos configuration for Active Directory

## Installation

1. Download and open the DMG file
2. Drag Network Share Mounter to your Applications folder
3. On first launch: Grant network access permissions when prompted

## For IT Administrators

### MDM Configuration

Network Share Mounter supports full MDM/Configuration Profile management:
- Centrally define network shares
- Automatic Kerberos configuration
- Enforce or suggest settings
- Compatible with Version 3 profiles

**New in Version 4:**
- **`mountPoint` parameter**: Define the local mount point name centrally via MDM
- **Backward compatible**: Existing MDM profiles work without changes
- **Profile system**: Deploy authentication profiles via MDM (optional)

### Migration from Version 3

Version 4 automatically migrates on first launch:
- ✅ Existing share configurations
- ✅ Keychain entries (converted to profiles)
- ✅ Kerberos settings
- ✅ MDM profiles

No manual steps required - the migration happens seamlessly in the background.

## Usage

### Adding a Network Share

1. Open Network Share Mounter preferences
2. Go to the "Network Shares" tab
3. Click the "+" button
4. Enter the share URL (e.g., `smb://server.local/share`)
5. Choose or create an authentication profile
6. Customize the local name if desired
7. Click "Save"

The share will be mounted automatically and on every login.

### Managing Authentication Profiles

1. Go to the "Authentication Profiles" tab
2. Click "+" to create a new profile
3. Enter a descriptive name
4. Choose profile type (Kerberos or Password)
5. Enter credentials
6. Assign colors/icons for easy identification

Profiles can be edited anytime, and changes apply to all associated shares.

### Renaming Mount Points

To change how a share appears on your system:

1. Select the share in the list
2. Click the edit button
3. Change the "Share Name" field
4. Click "Save Changes"

If the share is currently mounted, Network Share Mounter will automatically remount it at the new location.

## Troubleshooting

### Share Won't Mount

1. Check network connectivity to the server
2. Verify credentials in the authentication profile
3. Check Kerberos tickets: `klist` in Terminal
4. Review logs: Use Console.app and filter for "NetworkShareMounter"

### Duplicate Name Error

If you get a duplicate name error when adding a share, choose a different local name - each share must have a unique mount point name.

### Profile Assignment Issues

If a share shows "Profile assignment required":
1. Open preferences → Network Shares
2. Select the affected share
3. Manually assign an authentication profile
4. Click "Save Changes"


---

**Note**: This is a beta release. Please report any issues.
