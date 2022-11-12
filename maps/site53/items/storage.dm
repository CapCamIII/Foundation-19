/obj/item/storage/box/ifak
	name = "first-aid kit"
	desc = "A box decorated in warning colors that contains a limited supply of survival tools. The panel and orange stripe indicate this one as the security variant."
	icon_state = "survivaleng"
	startswith = list(
		/obj/item/storage/pill_bottle/tramadol = 1,
		///obj/item/weapon/reagent_containers/pill/amnestics/classa = 1,
		///obj/item/weapon/reagent_containers/hypospray/autoinjector/combatpain = 1,
		/obj/item/stack/medical/bruise_pack = 1,
		/obj/item/stack/medical/ointment = 1,
		/obj/item/stack/medical/splint/ghetto = 1)

/obj/item/storage/box/mk11_case
	name = "MK11 Whisper Case"
	desc = "A small box designed to store an MK11 Whisper for long periods of time without requiring maintence."
	startswith = list(
		/obj/item/gun/projectile/pistol/mk11 = 1,
		/obj/item/ammo_magazine/scp/mk9 = 3)

/obj/item/stamp/approved
	name = "\improper APPROVED rubber stamp"
	icon_state = "stamp-approve"
