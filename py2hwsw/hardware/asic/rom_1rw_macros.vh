// Default ROM macro include (behavioral fallback).
// Overwritten by `openram-gen`.
begin : g_behavioral
    rom_1rw_behavioral #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .HEXFILE(HEXFILE)
    ) u_rom (
        .clk  (clk),
        .en   (en),
        .addr (addr),
        .dout (dout),
        .VPWR(VPWR),
        .VGND(VGND)
    );
end
