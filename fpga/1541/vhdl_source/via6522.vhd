library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity via6522 is
port (
    clock       : in  std_logic;
    clock_en    : in  std_logic; -- for counters and stuff
    reset       : in  std_logic;
    
    addr        : in  std_logic_vector(3 downto 0);
    wen         : in  std_logic;
    ren         : in  std_logic;
    data_in     : in  std_logic_vector(7 downto 0);
    data_out    : out std_logic_vector(7 downto 0);

    -- pio --
    port_a_o    : out std_logic_vector(7 downto 0);
    port_a_t    : out std_logic_vector(7 downto 0);
    port_a_i    : in  std_logic_vector(7 downto 0);
    
    port_b_o    : out std_logic_vector(7 downto 0);
    port_b_t    : out std_logic_vector(7 downto 0);
    port_b_i    : in  std_logic_vector(7 downto 0);

    -- handshake pins
    ca1_i       : in  std_logic;

    ca2_o       : out std_logic;
    ca2_i       : in  std_logic;
    ca2_t       : out std_logic;
    
    cb1_o       : out std_logic;
    cb1_i       : in  std_logic;
    cb1_t       : out std_logic;
    
    cb2_o       : out std_logic;
    cb2_i       : in  std_logic;
    cb2_t       : out std_logic;

    irq         : out std_logic );
    
end via6522;

architecture Gideon of via6522 is

    type pio_t is
    record
        pra     : std_logic_vector(7 downto 0);
        ddra    : std_logic_vector(7 downto 0);
        prb     : std_logic_vector(7 downto 0);
        ddrb    : std_logic_vector(7 downto 0);
    end record;
    
    constant pio_default : pio_t := (others => (others => '0'));
    constant latch_reset_pattern : std_logic_vector(15 downto 0) := X"01AA";

    signal pio_i         : pio_t;
    
    signal irq_mask      : std_logic_vector(6 downto 0) := (others => '0');
    signal irq_flags     : std_logic_vector(6 downto 0) := (others => '0');
    signal irq_events    : std_logic_vector(6 downto 0) := (others => '0');
    signal irq_out       : std_logic;
    
    signal timer_a_latch : std_logic_vector(15 downto 0) := latch_reset_pattern;
    signal timer_b_latch : std_logic_vector(7 downto 0) := latch_reset_pattern(7 downto 0);
    signal timer_a_count : std_logic_vector(15 downto 0) := latch_reset_pattern;
    signal timer_b_count : std_logic_vector(15 downto 0) := latch_reset_pattern;
    signal timer_a_out   : std_logic;
    signal timer_b_tick  : std_logic;
                         
    signal acr, pcr      : std_logic_vector(7 downto 0) := X"00";
    signal shift_reg     : std_logic_vector(7 downto 0) := X"00";
    signal serport_en    : std_logic;
    signal ser_cb2_o     : std_logic;
    signal hs_cb2_o      : std_logic;
        
    alias  ca2_event     : std_logic is irq_events(0);
    alias  ca1_event     : std_logic is irq_events(1);
    alias  serial_event  : std_logic is irq_events(2);
    alias  cb2_event     : std_logic is irq_events(3);
    alias  cb1_event     : std_logic is irq_events(4);
    alias  timer_b_event : std_logic is irq_events(5);
    alias  timer_a_event : std_logic is irq_events(6);

    alias  ca2_flag      : std_logic is irq_flags(0);
    alias  ca1_flag      : std_logic is irq_flags(1);
    alias  serial_flag   : std_logic is irq_flags(2);
    alias  cb2_flag      : std_logic is irq_flags(3);
    alias  cb1_flag      : std_logic is irq_flags(4);
    alias  timer_b_flag  : std_logic is irq_flags(5);
    alias  timer_a_flag  : std_logic is irq_flags(6);

    alias tmr_a_output_en   : std_logic is acr(7);
    alias tmr_a_freerun     : std_logic is acr(6);
    alias tmr_b_count_mode  : std_logic is acr(5);
    alias shift_dir         : std_logic is acr(4);
    alias shift_clk_sel     : std_logic_vector(1 downto 0)  is acr(3 downto 2);
    alias shift_mode_control     : std_logic_vector(2 downto 0)  is acr(4 downto 2);
    alias pb_latch_en       : std_logic is acr(1);
    alias pa_latch_en       : std_logic is acr(0);
    
    alias cb2_is_output     : std_logic is pcr(7);
    alias cb2_edge_select   : std_logic is pcr(6); -- for when CB2 is input
    alias cb2_no_irq_clr    : std_logic is pcr(5); -- for when CB2 is input
    alias cb2_out_mode      : std_logic_vector(1 downto 0) is pcr(6 downto 5);
    alias cb1_edge_select   : std_logic is pcr(4);
    
    alias ca2_is_output     : std_logic is pcr(3);
    alias ca2_edge_select   : std_logic is pcr(2); -- for when CA2 is input
    alias ca2_no_irq_clr    : std_logic is pcr(1); -- for when CA2 is input
    alias ca2_out_mode      : std_logic_vector(1 downto 0) is pcr(2 downto 1);
    alias ca1_edge_select   : std_logic is pcr(0);
    
    signal ira, irb         : std_logic_vector(7 downto 0) := (others => '0');
    
    signal pb_latch_ready   : std_logic := '0';
    signal pa_latch_ready   : std_logic := '0';
    
    signal write_t1c_h      : std_logic;
    signal write_t2c_h      : std_logic;
    signal write_acr        : std_logic;
    signal write_t1_latch_l : std_logic;
    signal write_t1_latch_h : std_logic;
    signal write_t2_latch_l : std_logic;

    signal ca1_c, ca2_c     : std_logic;
    signal cb1_c, cb2_c     : std_logic;
    signal ca1_d, ca2_d     : std_logic;
    signal cb1_d, cb2_d     : std_logic;
    
    signal set_ca2_low      : std_logic;
    signal set_cb2_low      : std_logic;
begin
    irq <= irq_out;
    
    irq_out <= '0' when (irq_flags and irq_mask) = "0000000" else '1';
    
    write_t1c_h <= '1' when addr = X"5" and wen='1' else '0';
    write_t2c_h <= '1' when addr = X"9" and wen='1' else '0';
    write_acr <= '1' when addr = X"B" and wen='1' else '0';
    write_t1_latch_l <= '1' when (addr = X"4" or addr = X"6") and wen='1' else '0';
    write_t1_latch_h <= '1' when (addr = X"5" or addr = X"7") and wen='1' else '0';
    write_t2_latch_l <= '1' when addr = X"8" and wen='1' else '0';    

--    input latches
    ira <= port_a_i when pa_latch_ready='0';
    irb <= port_b_i when pb_latch_ready='0';
    pa_latch_ready <= '1' when (ca1_event='1') and (pa_latch_en='1') and (pa_latch_ready='0') else
        '0' when (pa_latch_en='0') or (ren='1' and addr=X"1");
    pb_latch_ready <= '1' when (cb1_event='1') and (pb_latch_en='1') and (pb_latch_ready='0') else
        '0' when (pb_latch_en='0') or (ren='1' and addr=X"0");        

    ca1_event <= (ca1_c xor ca1_d) and (ca1_d xor ca1_edge_select);
    ca2_event <= (ca2_c xor ca2_d) and (ca2_d xor ca2_edge_select);
    cb1_event <= (cb1_c xor cb1_d) and (cb1_d xor cb1_edge_select);
    cb2_event <= (cb2_c xor cb2_d) and (cb2_d xor cb2_edge_select);

    ca2_t <= ca2_is_output;
    cb2_t <= cb2_is_output when serport_en='0' else shift_dir;
    cb2_o <= hs_cb2_o      when serport_en='0' else ser_cb2_o;

    process(clock)
    begin
        if rising_edge(clock) then            
            -- CA1/CA2/CB1/CB2 edge detect flip flops
            ca1_c <= To_X01(ca1_i);
            ca2_c <= To_X01(ca2_i);
            cb1_c <= To_X01(cb1_i);
            cb2_c <= To_X01(cb2_i);

            ca1_d <= ca1_c;
            ca2_d <= ca2_c;
            cb1_d <= cb1_c;
            cb2_d <= cb2_c;

            -- CA2 output logic
            case ca2_out_mode is
            when "00" =>
                if ca1_event='1' then
                    ca2_o <= '1';
                elsif (ren='1' or wen='1') and addr=X"1" then
                    ca2_o <= '0';
                end if;
            
            when "01" =>
                if clock_en='1' then
                    ca2_o <= not set_ca2_low;
                    set_ca2_low <= '0';
                end if;
                if (ren='1' or wen='1') and addr=X"1" then
                    if clock_en='1' then
                        ca2_o <= '0';
                    else
                        set_ca2_low <= '1';
                    end if;
                end if;
                                
            when "10" =>
                ca2_o <= '0';
            
            when "11" =>
                ca2_o <= '1';
            
            when others =>
                null;
            end case;

            -- CB2 output logic
            case cb2_out_mode is
            when "00" =>
                if cb1_event='1' then
                    hs_cb2_o <= '1';
                elsif (ren='1' or wen='1') and addr=X"0" then
                    hs_cb2_o <= '0';
                end if;
            
            when "01" =>
                if clock_en='1' then
                    hs_cb2_o <= not set_cb2_low;
                    set_cb2_low <= '0';
                end if;
                if (ren='1' or wen='1') and addr=X"0" then
                    if clock_en='1' then
                        hs_cb2_o <= '0';
                    else
                        set_cb2_low <= '1';
                    end if;
                end if;
                                
            when "10" =>
                hs_cb2_o <= '0';
            
            when "11" =>
                hs_cb2_o <= '1';
            
            when others =>
                null;
            end case;

            -- Interrupt logic
            irq_flags <= irq_flags or irq_events;
            
            -- Writes --
            if wen='1' then
                case addr is
                when X"0" => -- ORB
                    pio_i.prb <= data_in;
                    if cb2_no_irq_clr='0' then
                        cb2_flag <= '0';
                    end if;
                    cb1_flag <= '0';
                
                when X"1" => -- ORA
                    pio_i.pra <= data_in;
                    if ca2_no_irq_clr='0' then
                        ca2_flag <= '0';
                    end if;
                    ca1_flag <= '0';
                    
                when X"2" => -- DDRB
                    pio_i.ddrb <= data_in;
                
                when X"3" => -- DDRA
                    pio_i.ddra <= data_in;
                    
                when X"4" => -- TA LO counter (write=latch)
                    timer_a_latch(7 downto 0) <= data_in;
                    
                when X"5" => -- TA HI counter
                    timer_a_latch(15 downto 8) <= data_in;
                    timer_a_flag <= '0';
                    
                when X"6" => -- TA LO latch
                    timer_a_latch(7 downto 0) <= data_in;
                    
                when X"7" => -- TA HI latch
                    timer_a_latch(15 downto 8) <= data_in;
                    timer_a_flag <= '0';
                    
                when X"8" => -- TB LO latch
                    timer_b_latch(7 downto 0) <= data_in;
                    
                when X"9" => -- TB HI counter
                    timer_b_flag <= '0';
                
                when X"A" => -- Serial port
                    serial_flag <= '0';
                    
                when X"B" => -- ACR (Auxiliary Control Register)
                    acr <= data_in;
                    
                when X"C" => -- PCR (Peripheral Control Register)
                    pcr <= data_in;
                                    
                when X"D" => -- IFR
                    irq_flags <= irq_flags and not data_in(6 downto 0);
                    
                when X"E" => -- IER
                    if data_in(7)='1' then -- set
                        irq_mask <= irq_mask or data_in(6 downto 0);
                    else -- clear
                        irq_mask <= irq_mask and not data_in(6 downto 0);
                    end if;
                
                when X"F" => -- ORA no handshake
                    pio_i.pra <= data_in;
                    if ca2_no_irq_clr='0' then
                        ca2_flag <= '0';
                    end if;
                    ca1_flag <= '0';

                when others =>
                    null;
                end case;
            end if;
            
            -- Reads --
            
            case addr is
            when X"0" => -- ORB
                --Port B reads its own output register for pins set to output.
                data_out(0) <= (pio_i.prb(0) and pio_i.ddrb(0)) or (irb(0) and not pio_i.ddrb(0));
                data_out(1) <= (pio_i.prb(1) and pio_i.ddrb(1)) or (irb(1) and not pio_i.ddrb(1));
                data_out(2) <= (pio_i.prb(2) and pio_i.ddrb(2)) or (irb(2) and not pio_i.ddrb(2));
                data_out(3) <= (pio_i.prb(3) and pio_i.ddrb(3)) or (irb(3) and not pio_i.ddrb(3));
                data_out(4) <= (pio_i.prb(4) and pio_i.ddrb(4)) or (irb(4) and not pio_i.ddrb(4));
                data_out(5) <= (pio_i.prb(5) and pio_i.ddrb(5)) or (irb(5) and not pio_i.ddrb(5));
                data_out(6) <= (pio_i.prb(6) and pio_i.ddrb(6)) or (irb(6) and not pio_i.ddrb(6));
                data_out(7) <= (((pio_i.prb(7) and pio_i.ddrb(7)) or (irb(7) and not pio_i.ddrb(7))) and (not tmr_a_output_en)) or (tmr_a_output_en and timer_a_out);
                
                if cb2_no_irq_clr='0' and ren='1' then
                    cb2_flag <= '0';
                end if;
                if ren='1' then
                    cb1_flag <= '0';
                end if;
                                            
            when X"1" => -- ORA
                data_out <= ira;
                if ca2_no_irq_clr='0' and ren='1' then
                    ca2_flag <= '0';
                end if;
                if ren='1' then
                    ca1_flag <= '0';
                end if;
                
            when X"2" => -- DDRB
                data_out <= pio_i.ddrb;
            
            when X"3" => -- DDRA
                data_out <= pio_i.ddrb;
                
            when X"4" => -- TA LO counter
                data_out <= timer_a_count(7 downto 0);
                if ren='1' then
                    timer_a_flag <= '0';
                end if;
                
            when X"5" => -- TA HI counter
                data_out <= timer_a_count(15 downto 8);
                
            when X"6" => -- TA LO latch
                data_out <= timer_a_latch(7 downto 0);
                
            when X"7" => -- TA HI latch
                data_out <= timer_a_latch(15 downto 8);
                
            when X"8" => -- TA LO counter
                data_out <= timer_b_count(7 downto 0);
                if ren='1' then
                    timer_b_flag <= '0';
                end if;
                
            when X"9" => -- TA HI counter
                data_out <= timer_b_count(15 downto 8);

            when X"A" => -- SR
                data_out  <= shift_reg;
                if ren='1' then
                    serial_flag <= '0';
                end if;

            when X"B" => -- ACR
                data_out  <= acr;
                
            when X"C" => -- PCR
                data_out  <= pcr;
                
            when X"D" => -- IFR
                data_out  <= irq_out & irq_flags;
                
            when X"E" => -- IER
                data_out  <= '0' & irq_mask;
                
            when X"F" => -- ORA
                data_out  <= ira;

            when others =>
                null;
            end case;
            
            if reset='1' then
                pio_i         <= pio_default;
                irq_mask      <= (others => '0');
                irq_flags     <= (others => '0');
                acr           <= (others => '0');
                pcr           <= (others => '0');
                ca2_o         <= '1';
                hs_cb2_o      <= '1';
                set_ca2_low   <= '0';
                set_cb2_low   <= '0';
                timer_a_latch  <= latch_reset_pattern;
                timer_b_latch  <= latch_reset_pattern(7 downto 0);
            end if;
        end if;
    end process;

    -- PIO Out select --
	--PB7 in timer out mode: When acr bit 7 is 1 then the CPU always reads the timer output on port b reads of bit 7, however if the pin is in input mode then the pin PB7 will not be driven by the timer but will output a 1 as normal for pins set to input.
    port_a_o             <= pio_i.pra;
    port_b_o(6 downto 0) <= pio_i.prb(6 downto 0);
    port_b_o(7) <= pio_i.prb(7) when tmr_a_output_en='0' or pio_i.ddrb(7)='0' else timer_a_out;
    
    port_a_t             <= pio_i.ddra;
    port_b_t             <= pio_i.ddrb;    

    -- Timer A
    tmr_a: block
        signal timer_a_reload        : std_logic;
        signal timer_a_post_oneshot        : std_logic;
    begin
        process(clock)
        begin
            if rising_edge(clock) then
                timer_a_event <= '0';
    
                if clock_en='1' then
                    -- Always count, or load
                        
                    if timer_a_reload = '1' then
                        -- Handle case where the latch is written by the CPU in the clock before reloading.
                        if write_t1_latch_l = '1' then
                            timer_a_count <= timer_a_latch(15 downto 8) & data_in;
                        elsif write_t1_latch_h = '1' then
                             timer_a_count <= data_in & timer_a_latch(7 downto 0);
                        else 
                            timer_a_count <= timer_a_latch;
                        end if;
                        timer_a_reload <= '0';                        
                    else                        
                        if timer_a_count = X"0000" then
                            -- Generate an event if we were triggered
                            -- Timer a reloads in both free run and one shot
                            timer_a_reload <= '1';
                            if tmr_a_freerun = '1' and timer_a_post_oneshot = '0' then
                                timer_a_event  <= '1';
                                -- toggle output
                                timer_a_out    <= not timer_a_out;
                            else
                                if (timer_a_post_oneshot = '0') then
                                    timer_a_post_oneshot <= '1';
                                    timer_a_event  <= '1';
                                    -- Toggle output
                                    timer_a_out    <= not timer_a_out;
                                end if;
                            end if;
                        end if;
                        -- Timer continues to count in both free run and one shot.
                        timer_a_count <= timer_a_count - X"0001";
                    end if;
                end if;
                
                if write_t1c_h = '1' then
                    timer_a_count <= data_in & timer_a_latch(7 downto 0);
                    timer_a_reload <= '0';
                    timer_a_post_oneshot <= '0';                    
                end if;
                                                    
                if write_acr = '1' or write_t1c_h = '1' then
                    timer_a_out    <= not tmr_a_output_en;
                end if;

                if reset='1' then
                    timer_a_out    <= '0';
                    timer_a_count  <= latch_reset_pattern;
                    timer_a_reload <= '0';
                    timer_a_post_oneshot <= '0';
                end if;
            end if;
        end process;
    end block tmr_a;
    
    -- Timer B
    tmr_b: block
        signal timer_b_reload        : std_logic;
        signal timer_b_post_oneshot  : std_logic;
        signal pb6_c, pb6_d          : std_logic;
    begin
        process(clock)
            variable timer_b_decrement   : std_logic;
        begin
            if rising_edge(clock) then
                timer_b_event <= '0';
                timer_b_tick  <= '0';
                pb6_c <= port_b_i(6);
    
                timer_b_decrement := '0';
                if clock_en='1' then
                
                    pb6_d <= pb6_c;

                    if timer_b_reload = '1' then
                        -- Handle case where the latch is written by the CPU in the clock before reloading.
                        if write_t2_latch_l = '1' then 
                            timer_b_count <= X"00" & data_in;
                        else
                            timer_b_count <= X"00" & timer_b_latch(7 downto 0);
                        end if;
                        timer_b_reload <= '0';
                    else
                        if tmr_b_count_mode = '1' then
                            if (pb6_d='0' and pb6_c='1') then
                                 timer_b_decrement := '1';
                            end if;
                        else -- one shot or used for shift register
                            timer_b_decrement := '1';
                        end if;    
                        
                        if timer_b_decrement = '1' then
                            if timer_b_count = X"0000" then
                                if (timer_b_post_oneshot = '0') then
                                    timer_b_post_oneshot <= '1';
                                    timer_b_event  <= '1';
                                end if;
                                timer_b_tick <= '1';
                                case shift_mode_control is
                                when "001" | "101" | "100" =>
                                    timer_b_reload <= '1';
                                when others =>
                                    null;
                                end case;
                            end if;
                            timer_b_count <= timer_b_count - X"0001";
                        end if;
                    end if;
                end if;
                
                if write_t2c_h = '1' then
                    timer_b_count <= data_in & timer_b_latch(7 downto 0);
                    timer_b_reload <= '0';
                    timer_b_post_oneshot <= '0';
                end if;

                if reset='1' then
                    timer_b_count  <= latch_reset_pattern;
                    timer_b_reload <= '0';
                    timer_b_post_oneshot <= '0';
                end if;
            end if;
        end process;
    end block tmr_b;
    
    ser: block
        signal shift_clock_d : std_logic;
        signal shift_clock   : std_logic;
        signal shift_tick_r  : std_logic;
        signal shift_tick_f  : std_logic;
        signal cb1_c, cb2_c  : std_logic;
        signal mpu_write     : std_logic;
        signal mpu_read      : std_logic;
        signal bit_cnt       : integer range 0 to 7;
        signal shift_active  : std_logic;
    begin
        process(clock)
        begin
            if rising_edge(clock) then
                case shift_clk_sel is
                when "10" =>
                    if shift_active='0' then
                        shift_clock <= '1';
                    elsif clock_en='1' then
                        shift_clock <= not shift_clock;
                    end if;
                
                when "00"|"01" =>
                    if shift_active='0' then
                        shift_clock <= '1';
                    elsif timer_b_tick='1' then
                        shift_clock <= not shift_clock;
                    end if;
                
                when others => -- "11"
                    shift_clock <= To_X01(cb1_i);
                
                end case;
                shift_clock_d <= shift_clock;
            end if;
        end process;

        shift_tick_r <= not shift_clock_d and shift_clock;
        shift_tick_f <=     shift_clock_d and not shift_clock;
                
        cb1_t <= '0' when shift_clk_sel="11" else serport_en;
        cb1_o <= shift_clock;
        
        mpu_write <= wen  when addr=X"A" else '0';
        mpu_read  <= ren  when addr=X"A" else '0';
        
        serport_en <= shift_dir or shift_clk_sel(1) or shift_clk_sel(0);
        
        process(clock)
        begin
            if rising_edge(clock) then
                cb1_c  <= To_X01(cb1_i);
                cb2_c  <= To_X01(cb2_i);
                
                if shift_clk_sel = "00" then
                    bit_cnt <= 7;
                    if shift_dir='0' then -- disabled mode
                        shift_active <= '0';
                    end if;
                end if;
                
                if mpu_read='1' or mpu_write='1' then
                    bit_cnt      <= 7;
                    shift_active <= '1';
                    if mpu_write='1' then                        
                        shift_reg <= data_in;
                    end if;
                end if;

                serial_event <= '0';
                
                if shift_active='1' then
                    if shift_tick_f='1' then
                        ser_cb2_o <= shift_reg(7);
                    end if;

                    if shift_tick_r='1' then
                        if shift_dir='1' then -- output
                            shift_reg <= shift_reg(6 downto 0) & shift_reg(7);
                        else
                            shift_reg <= shift_reg(6 downto 0) & cb2_c;
                        end if;
                        
                        if bit_cnt=0 then
                            serial_event <= '1';
                            shift_active <= '0';
                        else
                            bit_cnt <= bit_cnt - 1;
                        end if;
                    end if;
                end if;
                if reset='1' then
                    shift_reg    <= (others => '1');
                    shift_active <= '0';
                    bit_cnt      <= 0;
                    ser_cb2_o    <= '1';
                end if;
            end if;
        end process;                
    end block ser;
end Gideon;
