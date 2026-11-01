//========================================================================
// Mesh Route Unit
//========================================================================

`ifndef NET_MESH_ROUTE_UNIT_V
`define NET_MESH_ROUTE_UNIT_V

module net_MeshRouteUnit
(
  input  logic [1:0] router_id,
  input  logic [1:0] dest,
  output logic [4:0] route
);

  always_comb begin
    logic x, x_dest, y, y_dest;
    route = 5'b0;
    x = router_id[0];
    y = router_id[1];
    x_dest = dest[0];
    y_dest = dest[1];

    route[4] = (x_dest == x) && (y_dest == y);
    if (x != x_dest) begin
      route[2] = (x_dest>x);
      route[3] = (x_dest<x);
    end
    else if (y != y_dest) begin
      route[0] = (y_dest<y);
      route[1] = (y_dest>y);
    end
  end


endmodule

`endif /* NET_MESH_ROUTE_UNIT_V */
