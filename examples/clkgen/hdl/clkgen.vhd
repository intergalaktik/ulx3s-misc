-- (c)EMARD
-- License=BSD

-- parametric ECP5 PLL generator
-- to see actual frequencies and phase shifts
-- trellis log/stdout : search for "MHz", "Derived", "frequency"
-- diamond log/*.mrp  : search for "MHz", "Frequency", "Phase", "Desired"

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity clkgen is
  generic
  (
    in_hz        : natural := 25000000;
    out0_hz      : natural := 25000000;
    out0_deg     : natural :=        0; -- keep 0
    out1_hz      : natural := 25000000;
    out1_deg     : natural :=        0;
    out2_hz      : natural := 25000000;
    out2_deg     : natural :=        0;
    out3_hz      : natural := 25000000;
    out3_deg     : natural :=        0;
    reset_en     : natural :=        0;
    standby_en   : natural :=        0;
    dynamic_en   : natural :=        0
  );
  port
  (
    clk_i        : in  std_logic;
    clk_o        : out std_logic_vector(3 downto 0);
    reset        : in  std_logic := '0';
    standby      : in  std_logic := '0';
    phasesel     : in  std_logic_vector(1 downto 0) := "00";
    phasedir,
    phasestep,
    phaseloadreg : std_logic := '0';
    locked       : out std_logic
  );
end;

architecture mix of clkgen is
  type T_clocks is record
    in_hz    : natural;
    out0_hz  : natural;
    out0_deg : natural;
    out1_hz  : natural;
    out1_deg : natural;
    out2_hz  : natural;
    out2_deg : natural;
    out3_hz  : natural;
    out3_deg : natural;
  end record T_clocks;
  
  type T_secondary is record
    div            : natural;
    freq_string    : string(0 to 9);
    freq           : natural;
    phase          : natural;
    cphase         : natural;
    fphase         : natural;
  end record T_secondary;
  type A_secondary is array(1 to 3) of T_secondary;

  type A_srequest is array(1 to 3) of natural;

  type T_params is record
    result         : T_clocks;
    refclk_div     : natural;
    feedback_div   : natural;
    output_div     : natural;
    fin_string     : string(0 to 9);
    fout_string    : string(0 to 9);
    fout           : natural;
    fvco           : natural;
    primary_cphase : natural;
    primary_fphase : natural;
    secondary      : A_secondary;
  end record T_params;

  function enabled_str(en: integer)
    return string is
    begin
      if en = 0 then
        return "DISABLED";
      else
        return "ENABLED";
      end if;
    end enabled_str;

  function Hz2MHz_str(int: integer)
    return string is
      constant base    :  natural := 10;
      constant digit   :  string(0 to 9) := "0123456789";
      variable temp    :  string(0 to 8) := (others => '0');
      variable power   :  natural := 1;
    begin
      -- convert integer to string
      for i in temp'high downto 0 loop
        temp(i) := digit(int/power mod base);
        power   := power * base;
      end loop;
      -- insert decimal point "123.456789"
      return temp(0 to 2) & "." & temp(3 to temp'high);
    end Hz2MHz_str;
  
  function F_ecp5pll(request: T_clocks)
    return T_params is
      constant PFD_MIN: natural :=   3125000;
      constant PFD_MAX: natural := 400000000;
      constant VCO_MIN: natural := 400000000;
      constant VCO_MAX: natural := 800000000;
      constant VCO_OPTIMAL: natural := (VCO_MIN+VCO_MAX)/2;
      variable params: T_params;
      variable input_div, feedback_div, output_div: natural;
      variable fpfd: natural;
      variable fout: natural;
      variable fvco: natural := 0;
      variable error: natural := 999999999;
      variable result: T_clocks;
      variable sfreq, sphase: A_srequest;
      variable div: natural;
      variable freq: natural;
      variable phase_compensation: natural;
      variable phase_count_x8: natural;
      variable cphase, fphase: natural;
      variable phase_shift: natural;
    begin
      sfreq(1)  := request.out1_hz;
      sphase(1) := request.out1_deg;
      sfreq(2)  := request.out2_hz;
      sphase(2) := request.out2_deg;
      sfreq(3)  := request.out3_hz;
      sphase(3) := request.out3_deg;
      -- generate primary output
      -- search all combinations 128*80*128=1.3e6 to find the best match
      for input_div in 1 to 128 loop
        fpfd := in_hz / input_div;
        if fpfd >= PFD_MIN and fpfd <= PFD_MAX then
          for feedback_div in 1 to 80 loop
            for output_div in 1 to 128 loop
              fvco := fpfd/1024 * feedback_div * output_div; -- /1024 to avoid overflow
              if fvco >= VCO_MIN/1024 and fvco <= VCO_MAX/1024 then
                fvco := fpfd * feedback_div * output_div;
                fout := fvco / output_div;
                if abs(fout-out0_hz) < error -- prefer least error
                or (fout=out0_hz and abs(fvco-VCO_OPTIMAL) < abs(params.fvco-VCO_OPTIMAL)) -- or if 0 error prefer closest to optimal VCO frequency
                then
                  error  := abs(fout-out0_hz);
                  phase_compensation    := (output_div+1)/2*8-8;
                  -- 180 must be added because of hardware, diamond does the same
                  phase_count_x8        := phase_compensation + output_div*(out0_deg+180)/360*8;
                  if phase_count_x8 > 1023 then -- we have problem
                    phase_count_x8 := phase_count_x8 mod (output_div*8); -- wraparound 360 deg
                  end if;
                  params.refclk_div     := input_div;
                  params.feedback_div   := feedback_div;
                  params.output_div     := output_div;
                  params.fin_string     := Hz2MHz_str(in_hz);
                  params.fout_string    := Hz2MHz_str(fout);
                  params.fout           := fout;
                  params.fvco           := fvco;
                  params.primary_cphase := phase_count_x8 / 8;
                  params.primary_fphase := phase_count_x8 mod 8;
                end if;
              end if;
            end loop;
          end loop;
        end if;
      end loop;
      -- generate secondary outputs
      for channel in 1 to 3 loop
        div  := params.fvco/sfreq(channel);
        freq := params.fvco/div;
        phase_compensation := div*8-8;
        phase_count_x8 := phase_compensation + 8*div*sphase(channel)/360;
        if phase_count_x8 > 1023 then -- we have problem
          phase_count_x8 := phase_count_x8 mod (div*8); -- wraparound 360 deg
        end if;
        cphase := phase_count_x8 / 8;
        fphase := phase_count_x8 mod 8;
        phase_shift := 8*div*sphase(channel)/360 * 360 / (8*div); -- reported phase shift
        params.secondary(channel).div         := div;
        params.secondary(channel).freq_string := Hz2MHz_str(freq);
        params.secondary(channel).freq        := freq;
        params.secondary(channel).phase       := phase_shift;
        params.secondary(channel).cphase      := cphase;
        params.secondary(channel).fphase      := fphase;
      end loop;
      params.result.in_hz    := request.in_hz;
      params.result.out0_hz  := natural(params.fout);
      params.result.out0_deg := 0; -- FIXME
      params.result.out1_hz  := natural(params.secondary(1).freq);
      params.result.out1_deg := natural(params.secondary(1).phase);
      params.result.out2_hz  := natural(params.secondary(2).freq);
      params.result.out2_deg := natural(params.secondary(2).phase);
      params.result.out3_hz  := natural(params.secondary(3).freq);
      params.result.out3_deg := natural(params.secondary(3).phase);
      return params;
    end F_ecp5pll;

  constant request : T_clocks := 
  (
    in_hz    => in_hz,
    out0_hz  => out0_hz,
    out0_deg => out0_deg,
    out1_hz  => out1_hz,
    out1_deg => out1_deg,
    out2_hz  => out2_hz,
    out2_deg => out2_deg,
    out3_hz  => out3_hz,
    out3_deg => out3_deg
  );
  constant params : T_params := F_ecp5pll(request);

  component EHXPLLL
  generic
  (
    CLKI_DIV         : integer := 1;
    CLKFB_DIV        : integer := 1;
    CLKOP_DIV        : integer := 8;
    CLKOS_DIV        : integer := 8;
    CLKOS2_DIV       : integer := 8;
    CLKOS3_DIV       : integer := 8;
    CLKOP_ENABLE     : string  := "ENABLED";
    CLKOS_ENABLE     : string  := "DISABLED";
    CLKOS2_ENABLE    : string  := "DISABLED";
    CLKOS3_ENABLE    : string  := "DISABLED";
    CLKOP_CPHASE     : integer := 0;
    CLKOS_CPHASE     : integer := 0;
    CLKOS2_CPHASE    : integer := 0;
    CLKOS3_CPHASE    : integer := 0;
    CLKOP_FPHASE     : integer := 0;
    CLKOS_FPHASE     : integer := 0;
    CLKOS2_FPHASE    : integer := 0;
    CLKOS3_FPHASE    : integer := 0;
    FEEDBK_PATH      : string  := "CLKOP";
    CLKOP_TRIM_POL   : string  := "RISING";
    CLKOP_TRIM_DELAY : integer := 0;
    CLKOS_TRIM_POL   : string  := "RISING";
    CLKOS_TRIM_DELAY : integer := 0;
    OUTDIVIDER_MUXA  : string  := "DIVA";
    OUTDIVIDER_MUXB  : string  := "DIVB";
    OUTDIVIDER_MUXC  : string  := "DIVC";
    OUTDIVIDER_MUXD  : string  := "DIVD";
    PLL_LOCK_MODE    : integer := 0;
    PLL_LOCK_DELAY   : integer := 200;
    STDBY_ENABLE     : string  := "DISABLED";
    REFIN_RESET      : string  := "DISABLED";
    SYNC_ENABLE      : string  := "DISABLED";
    INT_LOCK_STICKY  : string  := "ENABLED";
    DPHASE_SOURCE    : string  := "DISABLED";
    PLLRST_ENA       : string  := "DISABLED";
    INTFB_WAKE       : string  := "DISABLED" 
  );
  port
  (
    CLKI, CLKFB,
    RST, STDBY, PLLWAKESYNC,
    PHASESEL1, PHASESEL0, PHASEDIR, PHASESTEP, PHASELOADREG,
    ENCLKOP, ENCLKOS, ENCLKOS2, ENCLKOS3 : IN std_logic := 'X';
    CLKOP, CLKOS, CLKOS2, CLKOS3, LOCK, INTLOCK,
    REFCLK, CLKINTFB : OUT std_logic := 'X' 
  );
  end component;

  -- internal signal declarations
  signal CLKOP_t  : std_logic;
  signal CLKOS_t  : std_logic;
  signal CLKOS2_t : std_logic;
  signal CLKOS3_t : std_logic;
  signal REFCLK   : std_logic;
  signal phasesel_hw : std_logic_vector(1 downto 0);

  attribute FREQUENCY_PIN_CLKI   : string;
  attribute FREQUENCY_PIN_CLKOP  : string;
  attribute FREQUENCY_PIN_CLKOS  : string;
  attribute FREQUENCY_PIN_CLKOS2 : string;
  attribute FREQUENCY_PIN_CLKOS3 : string;
  attribute FREQUENCY_PIN_CLKI   of PLL_inst : label is params.fin_string;
  attribute FREQUENCY_PIN_CLKOP  of PLL_inst : label is params.fout_string;
  attribute FREQUENCY_PIN_CLKOS  of PLL_inst : label is params.secondary(1).freq_string;
  attribute FREQUENCY_PIN_CLKOS2 of PLL_inst : label is params.secondary(2).freq_string;
  attribute FREQUENCY_PIN_CLKOS3 of PLL_inst : label is params.secondary(3).freq_string;

  attribute ICP_CURRENT  : string;
  attribute LPF_RESISTOR : string;
  attribute ICP_CURRENT  of PLL_inst : label is "12";
  attribute LPF_RESISTOR of PLL_inst : label is "8";

  attribute syn_keep : boolean;
  attribute NGD_DRC_MASK : integer;
  attribute NGD_DRC_MASK of mix : architecture is 1;
begin
  G_dynamic: if dynamic_en /= 0 generate
  phasesel_hw <= phasesel-1;
  end generate;
  PLL_inst: EHXPLLL
  generic map
  (
    CLKI_DIV        =>  params.refclk_div,
    CLKFB_DIV       =>  params.feedback_div, 
    FEEDBK_PATH     => "CLKOP",

    OUTDIVIDER_MUXA => "DIVA",
    CLKOP_ENABLE    => "ENABLED",
    CLKOP_DIV       =>  params.output_div,
    CLKOP_CPHASE    =>  params.primary_cphase,
    CLKOP_FPHASE    =>  params.primary_fphase,
--  CLKOP_TRIM_DELAY=>  0, CLKOP_TRIM_POL=> "FALLING", 

    OUTDIVIDER_MUXB => "DIVB",
    CLKOS_ENABLE    => "ENABLED",
    CLKOS_DIV       =>  params.secondary(1).div,
    CLKOS_CPHASE    =>  params.secondary(1).cphase,
    CLKOS_FPHASE    =>  params.secondary(1).fphase,
--  CLKOS_TRIM_DELAY=>  0, CLKOS_TRIM_POL=> "FALLING", 

    OUTDIVIDER_MUXC => "DIVC",
    CLKOS2_ENABLE   => "ENABLED",
    CLKOS2_DIV      =>  params.secondary(2).div,
    CLKOS2_CPHASE   =>  params.secondary(2).cphase,
    CLKOS2_FPHASE   =>  params.secondary(2).fphase,

    OUTDIVIDER_MUXD => "DIVD",
    CLKOS3_ENABLE   => "ENABLED",
    CLKOS3_DIV      =>  params.secondary(3).div,
    CLKOS3_CPHASE   =>  params.secondary(3).cphase,
    CLKOS3_FPHASE   =>  params.secondary(3).fphase,

    INTFB_WAKE      => "DISABLED",
    PLLRST_ENA      =>  enabled_str(reset_en),
    STDBY_ENABLE    =>  enabled_str(standby_en),
    DPHASE_SOURCE   =>  enabled_str(dynamic_en),
    PLL_LOCK_MODE   =>  0
  )
  port map
  (
    CLKI => clk_i, CLKFB => CLKOP_t,
    RST => reset, STDBY => standby, PLLWAKESYNC => '0',
    PHASESEL1    => phasesel_hw(1),
    PHASESEL0    => phasesel_hw(0),
    PHASEDIR     => phasedir,
    PHASESTEP    => phasestep,
    PHASELOADREG => phaseloadreg,
    ENCLKOP =>'0', ENCLKOS => '0', ENCLKOS2 => '0', ENCLKOS3 => '0',
    CLKOP  => CLKOP_t,
    CLKOS  => CLKOS_t,
    CLKOS2 => CLKOS2_t,
    CLKOS3 => CLKOS3_t,
    INTLOCK => open, REFCLK => REFCLK, CLKINTFB => open,
    LOCK => locked
  );
  
  clk_o(0) <= clkop_t;
  clk_o(1) <= clkos_t;
  clk_o(2) <= clkos2_t;
  clk_o(3) <= clkos3_t;

end mix;
