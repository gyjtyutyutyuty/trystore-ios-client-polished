# Patch workspace guide

3105 patch packages target an app by its stable bundle identifier. They never store the app-container UUID, because that UUID changes across devices and reinstalls.

TryStore's preloaded patch catalog is delivered from its authenticated remote feed rather than shipped inside the IPA. A valid TryStore license and network connection are required for the initial catalog sync. Once a package has been fetched and verified, the app stores it in protected local application-support storage; this does not make a downloaded package impossible to extract from a device controlled by its user.

## Workspace layout

Creating a patch named `ABC` for `com.abc.xyz` creates this editable tree:

```text
On My iPhone/
└── 3105/
    └── Patches/
        └── ABC/
            └── com.abc.xyz/
                ├── Documents/
                │   └── config.json
                └── Library/
                    └── Preferences/
                        └── com.abc.xyz.plist
```

Everything below the bundle folder is a path relative to that app's data container. The top-level folder must be a valid bundle identifier, not a container UUID or an absolute `/var/mobile/...` path.

## Create a patch

### Start from the Patch tab

1. Open **Patch**, tap **+**, then choose **New Patch**.
2. Enter a project name and the target bundle identifier.
3. Optionally set a password. A package password cannot be changed later.
4. Tap **Done**. 3105 creates the project and its editable workspace.
5. Open **Files → 3105 Workspace → Patches → project name → bundle ID**.
6. Recreate the destination tree and place each replacement file at its final relative path.

For example, to replace `Library/Preferences/com.abc.xyz.plist`, put the replacement at exactly that path inside the `com.abc.xyz` folder. To add a complete folder, copy the folder into the correct parent path; every regular file below it becomes part of the patch.

### Start from an app-container file or folder

1. Open **Files**, enter an app container, then find the target file or folder.
2. Touch and hold it, then choose **Create Patch**.
3. 3105 captures the stable bundle identifier and relative path automatically and opens a patch draft.
4. Save the draft, open its workspace, and replace or rearrange the captured content as needed.

## Apply and restore

- **Apply** first synchronizes the workspace into the encrypted `.3105` package, resolves the current container from the bundle identifier, and validates every destination path.
- Existing targets are backed up before any replacement is written. Missing targets are created.
- Writes are journaled and verified. If applying fails partway through, 3105 attempts to roll the transaction back.
- **Restore Originals** returns files that existed before Apply, deletes files introduced by the patch, and removes directories created by the patch after they become empty.
- Restore verifies the app container, target path, and original backup. If a target changed while the patch was active, 3105 preserves those current bytes in the transaction recovery folder, then restores and verifies the saved original. It refuses only when the path, container, or original backup cannot be verified.

Keep the target app closed while applying or restoring a patch. Do not rename the bundle folder or move files outside it.

### iOS 27 remote-access prerequisites

On supported iOS 27 version/build pairs, patch apply and restore use the Airlift pairing tunnel rather than the local app-container browser. Complete pairing in SupportPatch or import a valid pairing file, and activate the supported loopback tunnel before applying or restoring. Apple Books must be installed and opened at least once because Airlift uses its Books sync service for temporary staging and recovery. If the tunnel is interrupted, reconnect and check the recorded transaction/receipt before retrying; do not rerun an operation while the previous transaction's state is unknown.

## Passwords

The app does not import or export packages. Patch packages reach the library as bundled resources or through the authenticated feed sync.

- On a new device or installation, a protected patch asks for its password once. 3105 stores the unlocked content key in Keychain, so it is not requested again for that package.
- Legacy v1 packages remain supported. An existing v1 package is not silently rewritten as v2.

## Safety rules

- Use patches only with apps and data you own.
- Keep a separate backup of important app data.
- Symbolic links, absolute paths, `..` traversal, invalid bundle identifiers, and duplicate destinations are rejected.
- Version 1.0.1 removes the old fixed payload-size and file-count ceiling, but available storage, memory, filesystem, and iOS limits still apply.
- Device-level access requires the supported iOS build and enterprise-signing setup documented in the README.
