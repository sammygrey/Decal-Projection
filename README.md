# Decal-Projection-Roblox
 An implementation of Valve's decal-projection algorithm in Roblox.

## NOTICE:
 Roblox now has an official decal projection API. For more information check out:
 - [Forum Post](https://devforum.roblox.com/t/update-projecting-decals-to-editablemesh/3386639/23)
 - [Creator Docs](https://create.roblox.com/docs/reference/engine/classes/EditableImage#DrawImageProjected)

### Description
 This is a port of the decal system used in Valve's Source Engine in Roblox using the [EditableMesh API](https://create.roblox.com/docs/reference/engine/classes/EditableMesh). As of right now the EditableMesh API is in Beta, so please be aware that any and all of the methods used may change or be removed.

 ### Process
 Implementation of Valve's algorithm comes down to the following steps:
 1. Provide a 'position/orientation/size in 3D space' (hereby labeled λ) against the surface of the mesh.
 2. Scale λ to the original dimensions of the mesh data to be used against the EditableMesh data.
 3. Bit-flag each vertex to figure out if it’s facing towards λ and if its depth against the plane is close enough to the surface. Any vertex facing away will nuke any polygons attached to it.
 4. Convert the vertices into decal UV space using a planar projection of the mesh geometry against λ. (I used PointToObjectSpace against λ as a CFrame)
 5. Bit-flag each vertex whose UVs are outside of the 0-1 range of values. If all vertices are outside, the polygon is culled. If all are inside, the polygon does not need to be clipped.
 6. Run 4 rounds of the Sutherland-Hodgman algorithm to clip polygons that had a mixture of vertices inside and outside of the 0-1 UV range box. This is done for all 4 edges of the decal using a double buffer that gets swapped back and forth on each edge so all newly added vertices are also included in the clipping procedure.
 7. The vertices that remain after the clipping are filled using a triangle fan. (i.e. verts[1], verts[i], verts[i + 1])

### Known Issues:
Just FYI: I'm not going to be fixing any of these as Roblox has already created their own proprietary API for decal-projection.
- Using this method there is a limited number of decals that can be projected onto any given mesh, currently that number is around 5-8 per mesh.
- There is a bug that causes parts of decals to be replicated along mesh seams, particularly where meshes branch out into multiple surfaces at one point. 
- Some projected decal polygons will appear at random points on the mesh. 



