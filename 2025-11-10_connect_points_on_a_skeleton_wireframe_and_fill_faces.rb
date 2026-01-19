mod = Sketchup.active_model
ent = mod.active_entities
sel = mod.selection

# --- Helpers ---------------------------------------------------------

def centroid(points)
  n = points.length.to_f
  sx = sy = sz = 0.0
  points.each do |p|
    sx += p.x
    sy += p.y
    sz += p.z
  end
  Geom::Point3d.new(sx / n, sy / n, sz / n)
end

# Mean distance between corresponding points of two paths
# (checks forward and reversed, returns the smaller mean)
def mean_path_distance(path_a, path_b)
  len = [path_a.length, path_b.length].min
  sum_forward = 0.0
  sum_reverse = 0.0

  len.times do |i|
    sum_forward += path_a[i].distance(path_b[i])
    sum_reverse += path_a[i].distance(path_b[len - 1 - i])
  end

  [sum_forward, sum_reverse].min / len.to_f
end

# --- Main ------------------------------------------------------------

mod.start_operation("Loft faces between curves", true)

# 1. Collect curves from selection (arcs or arbitrary curves)
curves = []
sel.each do |e|
  if e.is_a?(Sketchup::Curve)
    curves << e unless curves.include?(e)
  elsif e.is_a?(Sketchup::Edge) && e.curve
    c = e.curve
    curves << c unless curves.include?(c)
  end
end

if curves.length < 2
  UI.messagebox("Please select at least two curves/arcs.")
  mod.abort_operation
  return
end

# 2. Snapshot vertices of each curve as paths of Point3d
paths_raw = curves.map { |curve| curve.vertices.map { |v| v.position } }

# Ensure all paths have same number of points
expected_len = paths_raw.first.length
unless paths_raw.all? { |pts| pts.length == expected_len }
  UI.messagebox("Not all selected curves have the same segment count. Aborting.")
  mod.abort_operation
  return
end

# 3. Order curves roughly along their main axis, using centroids + nearest neighbor

centroids = paths_raw.map { |pts| centroid(pts) }

xs = centroids.map(&:x)
ys = centroids.map(&:y)
zs = centroids.map(&:z)

range_x = xs.max - xs.min
range_y = ys.max - ys.min
range_z = zs.max - zs.min

main_axis =
  if range_x >= range_y && range_x >= range_z
    :x
  elsif range_y >= range_x && range_y >= range_z
    :y
  else
    :z
  end

start_idx = (0...paths_raw.length).min_by { |i| centroids[i].send(main_axis) }

ordered_indices = [start_idx]
remaining = (0...paths_raw.length).to_a - ordered_indices

while !remaining.empty?
  last = ordered_indices.last
  best = remaining.min_by { |j| mean_path_distance(paths_raw[last], paths_raw[j]) }
  ordered_indices << best
  remaining.delete(best)
end

paths = ordered_indices.map { |i| paths_raw[i] }

# 4. Create faces between each pair of neighboring paths
#    For each segment index n, we build two triangles:
#    p00 = left[n],   p01 = left[n+1]
#    p10 = right[n],  p11 = right[n+1]
#    triangles: (p00, p10, p11) and (p00, p11, p01)
#    and we soften/hide the common diagonal.

(0...paths.length - 1).each do |i|
  left  = paths[i]
  right = paths[i + 1]

  # Align right path direction to left path
  d_start = left.first.distance(right.first)
  d_end   = left.first.distance(right.last)
  right.reverse! if d_end < d_start

  (0...(left.length - 1)).each do |n|
    p00 = left[n]
    p01 = left[n + 1]
    p10 = right[n]
    p11 = right[n + 1]

    # Build two triangles
    f1 = ent.add_face(p00, p10, p11)
    f2 = ent.add_face(p00, p11, p01)

    # If both faces were created, soften/hide their shared edge (the diagonal)
    if f1 && f2
      shared_edges = f1.edges & f2.edges
      diag = shared_edges.first
      if diag
        diag.soft   = true
        diag.smooth = true
        diag.hidden = true
      end
    end
  end
end

mod.commit_operation
