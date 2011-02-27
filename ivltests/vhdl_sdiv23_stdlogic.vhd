library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdiv23 is
  port (
    a_i : in signed (22 downto 0);
    b_i : in signed (22 downto 0);
    c_o : out signed (22 downto 0)
  );
end entity sdiv23; 

architecture rtl of sdiv23 is
begin
  c_o <= a_i / b_i;
end architecture rtl;

