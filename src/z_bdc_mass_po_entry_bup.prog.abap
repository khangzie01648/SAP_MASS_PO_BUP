*&---------------------------------------------------------------------*
*& Report  Z_BDC_MASS_PO_ENTRY_BUP
*&---------------------------------------------------------------------*
*& SAP BDC Multi-TCODE Engine
*&
*& Transaction routing:
*&   ZBDC_CONFIG_BUP -> Configuration / Onboarding
*&   ZBDC_RUN_BUP    -> Runtime / Operations
*&   Z_BDC_02_BUP    -> Legacy Runtime
*&---------------------------------------------------------------------*

REPORT z_bdc_mass_po_entry_bup.

*---------------------------------------------------------------------*
* Legacy core includes
*---------------------------------------------------------------------*
INCLUDE z_bdc_mass_po_entry_top_bup.
INCLUDE z_bdc_mass_po_entry_o01_bup.
INCLUDE z_bdc_mass_po_entry_i01_bup.
INCLUDE z_bdc_mass_po_entry_f01_bup.

*---------------------------------------------------------------------*
* Modular engine includes
*---------------------------------------------------------------------*
INCLUDE zbdc_mpe_m0_nav_bup.
INCLUDE zbdc_mpe_m0_util_bup.

INCLUDE zbdc_mpe_m1_source_bup.
INCLUDE zbdc_mpe_m1_parse_bup.
INCLUDE zbdc_mpe_m1_stage_bup.

INCLUDE zbdc_mpe_m2_map_bup.

INCLUDE zbdc_mpe_m3_valid_bup.
INCLUDE zbdc_mpe_m3_exec_bup.

INCLUDE zbdc_mpe_m4_dash_bup.
INCLUDE zbdc_mpe_m4_error_bup.

*---------------------------------------------------------------------*
* Application entry routing
*---------------------------------------------------------------------*
START-OF-SELECTION.

  CASE sy-tcode.

    WHEN 'ZBDC_CONFIG_BUP'.
      "Transaction 1:
      "Configuration / Onboarding for admin or consultant
      CALL SCREEN 0800.

    WHEN 'ZBDC_RUN_BUP'.
      "Transaction 2:
      "Daily Runtime / Operations for end users
      CALL SCREEN 0100.

    WHEN 'Z_BDC_02_BUP'.
      "Legacy transaction kept temporarily for compatibility
      CALL SCREEN 0100.

    WHEN OTHERS.
      "Direct execution from SE38 / SE80
      CALL SCREEN 0100.

  ENDCASE.
