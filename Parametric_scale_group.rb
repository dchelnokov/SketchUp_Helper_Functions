model = Sketchup.active_model
sel   = model.selection

should_be = 5130.mm

grp = sel.grep(Sketchup::Group).first
unless grp
  UI.messagebox("Select the group that contains the image and the reference edge.")
  return
end

ref_edge = grp.entities.grep(Sketchup::Edge).first
unless ref_edge
  UI.messagebox("No edge found inside the selected group.")
  return
end

# World-space length of the edge (robust even if group is already scaled/rotated)
t  = grp.transformation
p1 = ref_edge.start.position.transform(t)
p2 = ref_edge.end.position.transform(t)
currently_is = p1.distance(p2)

if currently_is <= 0
  UI.messagebox("Reference edge has zero length.")
  return
end

factor = should_be.to_f / currently_is.to_f

anchor = Geom::Point3d.new(0, 0, 0) # world origin
tr = Geom::Transformation.scaling(anchor, factor)

model.start_operation("Scale to reference length", true)
model.active_entities.transform_entities(tr, [grp])  # scale the group instance
model.commit_operation
