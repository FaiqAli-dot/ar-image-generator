# blender -b -P render_views.py -- <glb> <outdir> <az_step> <res>
import bpy,sys,math,json,os
from mathutils import Vector
a=sys.argv[sys.argv.index('--')+1:];glb,out,step,res=a[0],a[1],int(a[2]),int(a[3])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)  # importer converts glTF Y-up -> Blender Z-up (source untouched)
objs=[o for o in bpy.context.scene.objects if o.type=='MESH']
# robust bounds: 1st-99th percentile of vertices, ignores stray reconstruction floaters
import numpy as np
P=np.concatenate([np.array([o.matrix_world@v.co for v in o.data.vertices]) for o in objs])
mn=Vector(np.percentile(P,1,axis=0));mx=Vector(np.percentile(P,99,axis=0))
ctr=(mn+mx)/2;rad=(mx-mn).length/2
for m in bpy.data.materials:  # unlit: show baked texture as-is
  nt=m.node_tree;tex=[n for n in nt.nodes if n.type=='TEX_IMAGE']
  if not tex:continue
  em=nt.nodes.new('ShaderNodeEmission');o=nt.nodes.new('ShaderNodeOutputMaterial')
  nt.links.new(tex[0].outputs['Color'],em.inputs['Color']);nt.links.new(em.outputs[0],o.inputs[0]);nt.nodes.active=o;o.is_active_output=True
s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.device='CPU';s.cycles.samples=8;s.cycles.use_denoising=False
s.render.film_transparent=True;s.render.resolution_x=s.render.resolution_y=res;s.render.image_settings.color_mode='RGBA'
s.view_settings.view_transform='Standard'
w=bpy.data.worlds.new('w');w.color=(0,0,0);s.world=w
cd=bpy.data.cameras.new('c');cd.lens=50;cam=bpy.data.objects.new('c',cd);s.collection.objects.link(cam);s.camera=cam
fov=2*math.atan(cd.sensor_width/2/cd.lens);dist=rad/math.sin(fov/2)*1.05
os.makedirs(out,exist_ok=True);man=[]
for lab,el in (('low',10),('high',35)):
  for az in range(0,360,step):
    e,z=math.radians(el),math.radians(az)
    cam.location=ctr+Vector((dist*math.cos(e)*math.sin(z),-dist*math.cos(e)*math.cos(z),dist*math.sin(e)))
    cam.rotation_euler=(ctr-cam.location).to_track_quat('-Z','Y').to_euler()
    fn=f'azimuth_{az:03d}_elevation_{lab}.png';s.render.filepath=os.path.join(out,fn);bpy.ops.render.render(write_still=True)
    man.append(dict(path=fn,azimuth_deg=az,elevation_label=lab,elevation_deg=el,width=res,height=res,source='synthetic_render',status='rendered_unreviewed'))
json.dump(dict(source_glb=os.path.basename(glb),camera=dict(lens_mm=50,distance=dist,center=list(ctr)),bbox_min=list(mn),bbox_max=list(mx),views=man),open(os.path.join(out,'manifest.json'),'w'),indent=1)
