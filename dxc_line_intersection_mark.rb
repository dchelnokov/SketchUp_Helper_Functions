# dcx_line_intersection.rb
# SketchUp 2025 – Add a menu item to find intersection of two selected lines
require 'sketchup.rb'

module DCX
  module LineIntersection
    extend self

    TOL = 1e-3 # inches

    def point_on_edge?(pt, edge)
      a = edge.start.position
      b = edge.end.position
      ((pt.distance(a) + pt.distance(b)) - edge.length).abs <= TOL
    end

    def entity_to_line(ent)
      ent.respond_to?(:line) ? ent.line : nil
    end

    def valid_selection?(sel)
      return false unless sel.length == 2
      sel.all? { |e| e.is_a?(Sketchup::Edge) || e.is_a?(Sketchup::ConstructionLine) }
    end

    def run
      model = Sketchup.active_model
      sel   = model.selection

      unless valid_selection?(sel)
        UI.messagebox("Selected entities are not crossing or not supported.\n(Select exactly two Edges/ConstructionLines.)")
        return
      end

      e1, e2 = sel.to_a
      l1 = entity_to_line(e1)
      l2 = entity_to_line(e2)

      unless l1 && l2
        UI.messagebox("Selected entities are not crossing or not supported.")
        return
      end

      ipt = Geom.intersect_line_line(l1, l2)
      unless ipt
        UI.messagebox("Selected entities are not crossing or not supported.")
        return
      end

      if e1.is_a?(Sketchup::Edge) && !point_on_edge?(ipt, e1)
        UI.messagebox("Selected entities are not crossing within the edge extents.")
        return
      end
      if e2.is_a?(Sketchup::Edge) && !point_on_edge?(ipt, e2)
        UI.messagebox("Selected entities are not crossing within the edge extents.")
        return
      end

      # Treat collinear overlaps as not a single crossing (optional)
      v1 = l1[1]; v2 = l2[1]
      if v1.parallel?(v2)
        on1 = e1.is_a?(Sketchup::Edge) ? point_on_edge?(ipt, e1) : Geom.point_on_line?(ipt, l1)
        on2 = e2.is_a?(Sketchup::Edge) ? point_on_edge?(ipt, e2) : Geom.point_on_line?(ipt, l2)
        if on1 && on2
          UI.messagebox("Entities are collinear/overlapping – not treated as a single crossing.")
          return
        end
      end

      model.start_operation("Add Intersection Point", true)
      model.active_entities.add_cpoint(ipt)
      model.commit_operation
    end

    # --- Menu integration ---
    unless file_loaded?(__FILE__)
      # Use the modern "Extensions" menu (exists in current SketchUp versions)
      ext_menu = UI.menu("Extensions")
      dcx_menu = ext_menu.add_submenu("DCX Tools")
      dcx_menu.add_item("Add Intersection Point") { run }
      # Optional separator if you plan more tools:
      # dcx_menu.add_separator

      # (Optional) Also add to right-click context menu:
      UI.add_context_menu_handler do |menu|
        sel = Sketchup.active_model.selection
        next unless valid_selection?(sel)
        menu.add_item("Add Intersection Point") { run }
      end

      file_loaded(__FILE__)
    end
  end
end

