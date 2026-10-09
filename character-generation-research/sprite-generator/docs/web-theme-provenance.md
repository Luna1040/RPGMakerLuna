# Web theme provenance

The web UI vendors the required Wayfarer Forge editor appearance as an
independently maintained local copy. The source revision was
`7d204b92989d65a0bc1754d56add415f5e64d1b9`.

| Parent source | SHA-256 at vendoring | Local responsibility |
| --- | --- | --- |
| `src/styles.css` | `dfdae7d039bd13415c7d855b36dd4528cf0a9f31cd5e90bab0d514ebed5ad150` | Four palette and appearance recipes |
| `src/editor-buttons.scss` | `f79e1fab3b448bec8e74ed339feaccac4af387edb3985c696d653ad99e3bbb8a` | Button states |
| `src/editor-controls.scss` | `bfc984c6f647ee0a1ab700e94c6d623c3b22941667584cc73aa0674ccbbcb324` | Fields and controls |
| `src/editor-typography.scss` | `a53902b66f10abfa6adc9a297f94dfd65b8f82a02d979a65b2d92b3d4abdcde5` | Text roles |
| `src/editor-surfaces.scss` | `2e1b7e03f52b476b5ae8ac6b9f2957d7538908ffd28bb213fc3b3ab5432d3650` | Panel surfaces |
| `src/editor/NumberField.tsx` | `b2916b8637b73565b85e3c35b82f0607777e32b7691ed28a723b8c94e85b5a50` | Numeric behavior reference |
| `src/editor/EditorDialogShell.tsx` | `50e3074722ce3797f9b7f0c7bfd024a95beb2a2d8b016d49a28be85c52fb3191` | Dialog behavior reference |

The Inter and Inconsolata variable fonts are copied into `web/public/fonts`
with their OFL license notices. Their hashes are recorded below.

- Inter Variable: `29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031`
- Inter Variable Italic: `acd98e64795781b2058f07b18475e0ecee2a0fe2b42a49e2f9e37d0d6bf66ce6`
- Inter OFL: `5b9321a4298cfeb6b34354164a1c3afc3db114569984c502b9b35d988fd58c57`
- Inconsolata Variable: `23ded25b447074d00659392bf9b1123d89df55cb07b0ad9bfef3366d199b5fcb`
- Inconsolata OFL: `29bd0cfd0fb2a45f9b057c834a057724bae1f63b525a8ac83d3e7525706d9f80`

The app does not import parent files or use parent-relative build paths. Theme
updates are deliberate local changes and should update this provenance record.
