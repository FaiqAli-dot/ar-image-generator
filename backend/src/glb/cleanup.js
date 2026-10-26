/**
 * Suggest cleanup (table/floor/floaters) — never auto-delete by size/position alone.
 * Owner must accept/reject each suggestion.
 */

/**
 * @param {object} inspection from inspectGlb
 * @returns {{ suggestions: Array<object>, autoSafe: string[] }}
 */
export function suggestCleanup(inspection) {
  const suggestions = [];
  const autoSafe = [];

  if (!inspection?.meshes?.length) {
    return { suggestions, autoSafe };
  }

  const bbox = inspection.bbox;
  const meshes = inspection.meshes;
  const totalTris = Math.max(1, inspection.triangleEstimate || 1);

  // Heuristic: meshes with tiny triangle share near the global floor (lowest Y of bbox)
  // are *candidates* for table/turntable/floor fragments — shown for review only.
  if (bbox) {
    const floorY = bbox.min[1];
    const height = Math.max(1e-6, bbox.size[1]);
    const floorBand = floorY + height * 0.08;

    for (const m of meshes) {
      const share = m.triangles / totalTris;
      // Without per-mesh world bounds in JSON alone, use relative triangle share + name hints.
      const name = (m.name || "").toLowerCase();
      const nameHint =
        /floor|table|ground|plane|turntable|lazy|backdrop|env|shadow|capture/.test(name);

      if (nameHint) {
        suggestions.push({
          id: `mesh-name-${m.index}`,
          type: "env_name_hint",
          severity: "medium",
          meshIndex: m.index,
          meshName: m.name,
          triangles: m.triangles,
          reason: `Mesh name “${m.name}” suggests environment / capture geometry, not food.`,
          action: "exclude_mesh",
          autoApply: false,
        });
      } else if (share > 0 && share < 0.015 && m.triangles < 800) {
        suggestions.push({
          id: `mesh-tiny-${m.index}`,
          type: "tiny_fragment",
          severity: "low",
          meshIndex: m.index,
          meshName: m.name,
          triangles: m.triangles,
          triangleShare: Number(share.toFixed(4)),
          reason:
            "Very small mesh relative to the scene — may be a floater or stray fragment. Garnishes/skewers can look like this; review before excluding.",
          action: "exclude_mesh",
          autoApply: false,
          floorBandY: floorBand,
        });
      }
    }
  }

  if (inspection.triangleEstimate > 400_000) {
    suggestions.push({
      id: "decimate-hq",
      type: "decimation",
      severity: "info",
      reason: `~${inspection.triangleEstimate.toLocaleString()} triangles — safe UV-preserving simplify recommended for web/mobile (kept as separate optimized assets; original preserved).`,
      action: "simplify",
      autoApply: false,
      recommendedRatio: inspection.triangleEstimate > 1_000_000 ? 0.25 : 0.45,
    });
  }

  if (inspection.imageCount > 0) {
    suggestions.push({
      id: "texture-resize",
      type: "texture_resize",
      severity: "info",
      reason: `${inspection.imageCount} embedded image(s). Oversized textures will be resized for the mobile web variant (max 1024); HQ preview keeps higher res (max 2048).`,
      action: "resize_textures",
      autoApply: false,
    });
  }

  if (inspection.scaleHintMeters && !inspection.scaleHintMeters.likelyMeters) {
    suggestions.push({
      id: "scale-check",
      type: "scale",
      severity: "medium",
      reason: inspection.scaleHintMeters.note,
      action: "review_scale",
      autoApply: false,
    });
  }

  // Safe non-destructive notes (always applied as documentation, not geometry edits)
  autoSafe.push("original_glb_preserved");
  autoSafe.push("no_auto_mesh_deletion");

  return { suggestions, autoSafe };
}

/**
 * Apply accepted mesh exclusions via gltf-transform Document (mutates).
 * Only removes meshes whose indices were explicitly accepted.
 */
export async function applyMeshExclusions(document, acceptedSuggestionIds, suggestions) {
  const exclude = new Set();
  for (const s of suggestions || []) {
    if (!acceptedSuggestionIds?.includes(s.id)) continue;
    if (s.action === "exclude_mesh" && s.meshIndex != null) {
      exclude.add(s.meshIndex);
    }
  }
  if (exclude.size === 0) return { removed: [] };

  const root = document.getRoot();
  const meshes = root.listMeshes();
  const removed = [];
  for (const idx of exclude) {
    const mesh = meshes[idx];
    if (!mesh) continue;
    // Detach from nodes
    for (const node of root.listNodes()) {
      if (node.getMesh() === mesh) node.setMesh(null);
    }
    mesh.dispose();
    removed.push(idx);
  }
  return { removed };
}
