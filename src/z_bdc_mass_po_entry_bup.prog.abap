*&---------------------------------------------------------------------*
*& Report Z_BDC_MASS_PO_ENTRY
*&---------------------------------------------------------------------*
*& Capstone Project: Mass Purchase Order entry via custom BDC on ME21N
*& Main Hub and Automation Orchestrator
*&---------------------------------------------------------------------*
REPORT z_bdc_mass_po_entry_bup.

INCLUDE Z_BDC_MASS_PO_ENTRY_TOP_BUP.
*INCLUDE z_bdc_mass_po_entry_top.  " Global Data Definitions
INCLUDE Z_BDC_MASS_PO_ENTRY_O01_BUP.
*INCLUDE z_bdc_mass_po_entry_o01.  " Process Before Output (PBO) Modules
INCLUDE Z_BDC_MASS_PO_ENTRY_I01_BUP.
*INCLUDE z_bdc_mass_po_entry_i01.  " Process After Input (PAI) Modules
INCLUDE Z_BDC_MASS_PO_ENTRY_F01_BUP.
*INCLUDE z_bdc_mass_po_entry_f01.  " Form Subroutines & Business Logic

INCLUDE ZBDC_MPE_M0_NAV_BUP.

INCLUDE ZBDC_MPE_M0_UTIL_BUP.

INCLUDE ZBDC_MPE_M1_SOURCE_BUP.

INCLUDE ZBDC_MPE_M1_PARSE_BUP.

INCLUDE ZBDC_MPE_M1_STAGE_BUP.

INCLUDE ZBDC_MPE_M2_MAP_BUP.

INCLUDE ZBDC_MPE_M3_VALID_BUP.

INCLUDE ZBDC_MPE_M3_EXEC_BUP.

INCLUDE ZBDC_MPE_M4_DASH_BUP.

INCLUDE ZBDC_MPE_M4_ERROR_BUP.
