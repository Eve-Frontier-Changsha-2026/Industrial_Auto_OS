module industrial_core::mock_fuel;

use industrial_core::production_line::{Self, ProductionLine};

/// Demo only — deposit free fuel without owner check.
/// Remove or gate before mainnet deployment.
public entry fun mock_deposit_fuel(
    line: &mut ProductionLine,
    amount: u64,
) {
    production_line::add_fuel_internal(line, amount);
}
