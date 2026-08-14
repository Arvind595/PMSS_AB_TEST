-- AD3551R one-DAC bring-up support package.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ad3551r_test_pkg is
  subtype byte_t is std_logic_vector(7 downto 0);
  type byte_array_t is array (natural range <>) of byte_t;

  function is_hex_ascii(c : byte_t) return boolean;
  function ascii_to_nibble(c : byte_t) return std_logic_vector;
  function nibble_to_ascii(n : std_logic_vector(3 downto 0)) return byte_t;
end package;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package body ad3551r_test_pkg is
  function is_hex_ascii(c : byte_t) return boolean is
  begin
    return ((c >= x"30") and (c <= x"39")) or
           ((c >= x"41") and (c <= x"46")) or
           ((c >= x"61") and (c <= x"66"));
  end function;

  function ascii_to_nibble(c : byte_t) return std_logic_vector is
  begin
    if (c >= x"30") and (c <= x"39") then
      return c(3 downto 0);
    elsif (c >= x"41") and (c <= x"46") then
      return std_logic_vector(unsigned(c) - to_unsigned(16#37#, 8));
    elsif (c >= x"61") and (c <= x"66") then
      return std_logic_vector(unsigned(c) - to_unsigned(16#57#, 8));
    else
      return "0000";
    end if;
  end function;

  function nibble_to_ascii(n : std_logic_vector(3 downto 0)) return byte_t is
  begin
    if unsigned(n) < 10 then
      return std_logic_vector(to_unsigned(16#30#, 8) + resize(unsigned(n), 8));
    else
      return std_logic_vector(to_unsigned(16#41#, 8) + resize(unsigned(n), 8) - 10);
    end if;
  end function;
end package body;
