module PerpClines
  # --- Global settings ---
  @eps = 0.01.mm  # default tolerance (change via PerpClines.eps = 0.01.mm)

  def self.eps
    @eps
  end

  def self.eps=(length)
    @eps = length
  end

  # --- Helpers ---
  def self.unique_points_from_edges(edges)
    edges.flat_map { |e| [e.start.position, e.end.position] }.uniq
  end

  def self.noncollinear_triple_exists?(pts, eps)
    (0...pts.length - 2).each do |i|
      (i + 1...pts.length - 1).each do |j|
        (j + 1...pts.length).each do |k|
          v1 = pts[j] - pts[i]
          v2 = pts[k] - pts[i]
          next if v1.length <= eps || v2.length <= eps
          n = v1 * v2
          return true if n.length > eps
        end
      end
    end
    false
  end

  # Find the plane that maximizes the number of inlier edge endpoints.
  # Returns [plane, inlier_edges, outlier_edges]
  def self.best_plane_and_inliers(edges, eps: self.eps, max_tests: 400)
    pts = unique_points_from_edges(edges)
    return [nil, [], edges] if pts.length < 3
    return [nil, [], edges] unless noncollinear_triple_exists?(pts, eps)

    combos =
      if pts.length <= 12
        pts.combination(3).to_a
      else
        Array.new(max_tests) { pts.sample(3) }
      end

    best_plane = nil
    best_inlier_count = -1

    combos.each do |p1, p2, p3|
      v1 = p2 - p1
      v2 = p3 - p1
      n  = v1 * v2
      next if v1.length <= eps || v2.length <= eps || n.length <= eps

      plane =  Geom.fit_plane_to_points([p1, p2, p3])
      next unless plane # (nil if it can't fit, e.g. collinear)

      # Score by number of endpoints close to the plane
      inlier_endpoints = 0
      edges.each do |e|
        inlier_endpoints += 1 if e.start.position.distance_to_plane(plane).abs <= eps
        inlier_endpoints += 1 if e.end.position.distance_to_plane(plane).abs   <= eps
      end

      if inlier_endpoints > best_inlier_count
        best_inlier_count = inlier_endpoints
        best_plane = plane
        # early exit if everything is inlier
        break if best_inlier_count == edges.length * 2
      end
    end

    return [nil, [], edges] unless best_plane

    inlier_edges = edges.select { |e|
      e.start.position.distance_to_plane(best_plane).abs <= eps &&
      e.end.position.distance_to_plane(best_plane).abs   <= eps
    }
    outlier_edges = edges - inlier_edges

    [best_plane, inlier_edges, outlier_edges]
  end

  # Deselect edges that are not coplanar with the dominant plane.
  # Keeps non-edge selected entities unchanged.
  # Returns [inlier_edges, outlier_edges, plane]
  def self.trim_selection_to_coplanar_edges!(eps: self.eps)
    model = Sketchup.active_model
    sel   = model.selection

    edges  = sel.grep(Sketchup::Edge)
    others = sel.to_a - edges

    return [[], [], nil] if edges.empty?

    plane, inliers, outliers = best_plane_and_inliers(edges, eps: eps)

    # Update selection to show the user what's coplanar
    sel.clear
    sel.add(others) unless others.empty?
    sel.add(inliers) unless inliers.empty?

    [inliers, outliers, plane]
  end

  # --- Main tool: draw in-plane perpendicular clines into a helper group ---
  # mode:
  #   :in_context    -> group is created in model.active_entities (same edit context)
  #   :overlay_world -> group created at model root, points/vectors transformed via edit_transform
  def self.draw_normals_group(mode: :in_context, eps: self.eps, group_name: "Normals")
    model = Sketchup.active_model
    sel   = model.selection
    edges = sel.grep(Sketchup::Edge)
    return UI.messagebox("Select one or more edges.") if edges.empty?

    # Ensure same edit context (practical sanity check)
    # If you want to allow mixed parents, remove this and accept that results may be confusing.
    parents = edges.map(&:parent).uniq
    if parents.length != 1
      UI.messagebox("Please select edges from the same edit context (same group/component).")
      return
    end

    plane_fit = Geom.fit_plane_to_points(unique_points_from_edges(edges))
    max_dev = unique_points_from_edges(edges).map { |p| p.distance_to_plane(plane_fit).abs }.max

    if max_dev > eps
      # Auto-trim selection to dominant plane
      inliers, outliers, plane = trim_selection_to_coplanar_edges!(eps: eps)

      if inliers.empty?
        UI.messagebox("No coplanar subset found within tolerance (eps = #{eps.to_l}).")
        return
      end

      UI.messagebox("Trimmed selection to coplanar edges:\nKept: #{inliers.length}\nRemoved: #{outliers.length}\nTolerance: #{eps.to_l}")

      edges = inliers
    end

    # Recompute plane/normal from (possibly trimmed) edges
    pts    = unique_points_from_edges(edges)
    plane  = Geom.fit_plane_to_points(pts)
    normal = Geom::Vector3d.new(plane[0], plane[1], plane[2])

    target_ents = (mode == :overlay_world) ? model.entities : model.active_entities

    tr = nil
    if mode == :overlay_world
      tr = model.respond_to?(:edit_transform) ? model.edit_transform : Geom::Transformation.new
    end

    model.start_operation("Normals in Group", true)

    helper = target_ents.add_group
    helper.name = group_name

    edges.each do |e|
      p1  = e.start.position
      p2  = e.end.position
      v   = p2 - p1
      next if v.length <= eps

      mid = Geom.linear_combination(0.5, p1, 0.5, p2)

      dir = normal * v  # in-plane perpendicular
      next if dir.length <= eps
      dir.normalize!

      if mode == :overlay_world
        mid_w = mid.transform(tr)
        dir_w = dir.transform(tr)
        dir_w.normalize!
        helper.entities.add_cline(mid_w, dir_w)
      else
        helper.entities.add_cline(mid, dir)
      end
    end

    model.commit_operation
    helper
  end
end

# Example usage:
# PerpClines.eps = 0.01.mm
# PerpClines.draw_normals_group(mode: :in_context, group_name: "Arc normals")
