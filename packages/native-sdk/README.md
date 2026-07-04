# @native-sdk/cli

CLI tools for the [Native SDK](https://zero-native.dev), a Zig native app framework with secure WebView surfaces, native controls, and OS capabilities.

## Install

```bash
npm install -g @native-sdk/cli
```

## Usage

```bash
native init my_app --frontend vite
cd my_app
zig build run
```

The first run installs the generated frontend dependencies automatically.

Use WebViews for rich product UI, and add native windows, menus, shortcuts, views, dialogs, clipboard, credentials, and OS services where the platform should own the interaction.

## Commands

| Command | Description |
|---------|-------------|
| `native init [name] --frontend <next\|vite\|react\|svelte\|vue>` | Scaffold a new Native SDK project |
| `native dev --binary <path>` | Start the app with a managed frontend dev server |
| `native doctor` | Check host environment, WebView, manifest, and CEF |
| `native validate` | Validate `app.zon` against the manifest schema |
| `native package` | Package the app for distribution |
| `native bundle-assets` | Copy frontend assets into the build output |
| `native automate` | Interact with a running app's automation server |
| `native skills list` | List built-in AI agent skills |
| `native skills get <name>` | Output AI agent skill content |
| `native version` | Print the native version |

## More

See the [full documentation](https://zero-native.dev) for details on the app model, native controls, capabilities, bridge, security, and packaging.
