module GuideIntersectionMarkers
  # Default tolerance (Length). You can change it via:
  #   GuideIntersectionMarkers.eps = 0.01.mm
  DEFAULT_EPS = 0.001.mm
  @eps = DEFAULT_EPS

  class << self
    attr_reader :eps

    # Accepts Numeric with units (e.g. 0.01.mm) or a Length.
    def eps=(value)
      @eps = value.to_l
    end

    # Main entry:
    #   GuideIntersectionMarkers.mark_selected_intersections("MyGroupName")
    def mark_selected_intersections(group_name, eps = @eps)
      model = Sketchup.active_model
      ents  = model.active_entities
      sel   = model.selection

      clines = sel.grep(Sketchup::ConstructionLine).select(&:valid?)
      if clines.length < 2
        UI.messagebox("Select at least two construction lines (guides) and try again.")
        return 0
      end

      # Existing output group (if any)
      out_group = find_named_group(ents, group_name)

      # Cache known construction-point positions in *this editing context* plus the output group.
      known_pts = []
      known_pts.concat(ents.grep(Sketchup::ConstructionPoint).map(&:position))
      if out_group && out_group.valid?
        known_pts.concat(out_group.entities.grep(Sketchup::ConstructionPoint).map(&:position))
      end

      # Convert guides to line representations: [Point3d, Vector3d]
      lines = clines.map { |cl| to_infinite_line(cl) }.compact
      if lines.length < 2
        UI.messagebox("Could not read enough valid construction lines from selection.")
        return 0
      end

      added = 0

      # Wrapping in an undoable operation is important for performance and user experience. :contentReference[oaicite:1]{index=1}
      model.start_operation("Mark Guide Intersections", true)
      begin
        (0...lines.length - 1).each do |i|
          (i + 1...lines.length).each do |j|
            pt = intersection_point(lines[i], lines[j], eps)
            next unless pt
            next if point_exists?(pt, known_pts, eps)

            # Create group lazily (avoid empty group pitfalls). :contentReference[oaicite:2]{index=2}
            unless out_group && out_group.valid?
              out_group = ents.add_group
              out_group.name = group_name
            end

            out_group.entities.add_cpoint(pt)
            known_pts << pt
            added += 1
          end
        end

        model.commit_operation
      rescue => e
        model.abort_operation
        raise e
      end

      UI.messagebox("Added #{added} construction point(s) to group “#{group_name}”.")
      added
    end

    private

    def find_named_group(ents, name)
      ents.grep(Sketchup::Group).find { |g| g.valid? && g.name == name }
    end

    def to_infinite_line(cl)
      p = cl.position || cl.start || cl.end
      v = cl.direction
      return nil unless p && v && v.length > 0.0
      [p, v]
    end

    def point_exists?(pt, pts, eps)
      pts.any? { |p| p.distance(pt) <= eps }
    end

    def intersection_point(line1, line2, eps)
      # Exact intersection (infinite lines)
      pt = Geom.intersect_line_line(line1, line2)
      return pt if pt

      # Optional “near intersection”: if lines don't strictly intersect (often due to tiny non-coplanarity),
      # treat them as intersecting when their closest approach <= eps.
      v1 = line1[1]
      v2 = line2[1]
      return nil if v1.parallel?(v2)

      cpts = Geom.closest_points(line1, line2)
      return nil unless cpts && cpts.length == 2

      p1, p2 = cpts
      return nil unless p1.distance(p2) <= eps

      # Midpoint between closest points
      Geom.linear_combination(0.5, p1, 0.5, p2)
    end
  end
end
