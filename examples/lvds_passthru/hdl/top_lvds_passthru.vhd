-- (c)EMARD
-- License=BSD

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity top_lvds_passthru is
  generic
  (
    bits: integer := 27
  );
  port
  (
    clk_25mhz : in  std_logic;  -- main clock input from 25MHz clock source
    gn        : out std_logic_vector(8 downto 8);
    gp_i      : in  std_logic_vector(12 downto 9);
    gp_o      : out std_logic_vector(6 downto 3);
    led       : out std_logic_vector(7 downto 0)
  );
end;

architecture mix of top_lvds_passthru is
    type T_blink is array (0 to 3) of std_logic_vector(bits-1 downto 0);
    signal R_blink: T_blink;
    signal clocks: std_logic_vector(3 downto 0);
begin
    clkgen_inst: entity work.clkgen
    generic map
    (
        in_hz  => natural( 25.0e6),
      out0_hz  => natural( 20.0e6),
      out1_hz  => natural( 20.0e6),
      out1_deg =>          90,
      out2_hz  => natural( 20.0e6),
      out2_deg =>         180,
      out3_hz  => natural(  6.0e6),
      out3_deg =>         300
    )
    port map
    (
      clk_i => gp_i(12),
      clk_o => clocks,
      locked => led(7)
    );

    G_blinks: for i in 0 to 2
    generate
      process(clocks(i))
      begin
        if rising_edge(clocks(i)) then
          R_blink(i) <= R_blink(i)+1;
        end if;
        led(2*i+1 downto 2*i) <= R_blink(i)(bits-1 downto bits-2);
      end process;
    end generate;

    gn(8) <= '1'; -- normally PWM
    gp_o(6 downto 3) <= gp_i(12 downto 9);

end mix;
