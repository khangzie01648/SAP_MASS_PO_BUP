*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZBDC_SCT_DEF_BUP................................*
DATA:  BEGIN OF STATUS_ZBDC_SCT_DEF_BUP              .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZBDC_SCT_DEF_BUP              .
CONTROLS: TCTRL_ZBDC_SCT_DEF_BUP
            TYPE TABLEVIEW USING SCREEN '0001'.
*.........table declarations:.................................*
TABLES: *ZBDC_SCT_DEF_BUP              .
TABLES: ZBDC_SCT_DEF_BUP               .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
