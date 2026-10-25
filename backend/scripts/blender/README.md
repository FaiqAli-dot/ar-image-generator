# Luma High-Poly GLB -> synthetic view set
Source copied read-only to src/model.glb (original attachment untouched).
Requires: python3 + Pillow, numpy; Blender 4.2 (portable at /workspace/tools, override with BLENDER=).
    ./run.sh [glb] [az_step] [res]     # e.g. ./run.sh src/model.glb 10 1024  -> 36x2 = 72 views
Outputs: textures/ (raw embedded PNG atlases + textures.json + contact_sheet.png),
out/views_<step>deg_<res>/azimuth_XXX_elevation_{low,high}.png (RGBA, transparent bg), manifest.json, contact_sheet.png.
Render: Cycles CPU, unlit emission (baked texture as-is, no shadows), 50mm fixed lens, distance auto-fit to
1-99th percentile vertex bounds, orbit around that center; elevation low=10deg, high=35deg; azimuth 0 = -Y (front in Blender after glTF Y-up->Z-up import).
All images are SYNTHETIC renders of the reconstructed mesh, not original camera photos. Status 'rendered_unreviewed'.
