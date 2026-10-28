// Default macro include for SRAM wrapper (behavioral fallback).
// Overwritten by `openram-gen` if OpenRAM macros are configured.
begin : g_behavioral
    sram_1rw1r_behavioral #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_sram (
        .clk    (clk),
        .csb0   (csb0),
        .web0   (web0),
        .wmask0 (wmask0),
        .addr0  (addr0),
        .din0   (din0),
        .dout0  (dout0),
        .csb1   (csb1),
        .addr1  (addr1),
        .dout1  (dout1)
    );
end
