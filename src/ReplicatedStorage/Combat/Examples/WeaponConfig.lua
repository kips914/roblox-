--!strict
-- Copy this ModuleScript under a Tool and name it WeaponConfig.
-- The Tool also needs an Attachment or BasePart named Muzzle.

return {
	MuzzleName = "Muzzle",
	MagazineSize = 12,
	ReloadTimeSeconds = 3.2,
	FireIntervalSeconds = 0.42,
	MaxAimAngleDegrees = 89,
	AllowedShells = { "AP_30MM", "HE_30MM", "HEAT_30MM", "APFSDS_30MM" },

	-- Set one or more of these as Tool attributes to supply ammunition:
	-- Ammo_AP_30MM = 48, Ammo_HE_30MM = 24, Ammo_HEAT_30MM = 8, Ammo_APFSDS_30MM = 12
	-- CombatWeapon = true (required on the Tool)
}
