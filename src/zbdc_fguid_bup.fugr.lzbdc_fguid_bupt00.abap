*---------------------------------------------------------------------*
*    view related data declarations
*---------------------------------------------------------------------*
*...processing: ZBDC_FGUID_BUP..................................*
DATA:  BEGIN OF STATUS_ZBDC_FGUID_BUP                .   "state vector
         INCLUDE STRUCTURE VIMSTATUS.
DATA:  END OF STATUS_ZBDC_FGUID_BUP                .
CONTROLS: TCTRL_ZBDC_FGUID_BUP
            TYPE TABLEVIEW USING SCREEN '9000'.
*.........table declarations:.................................*
TABLES: *ZBDC_FGUID_BUP                .
TABLES: ZBDC_FGUID_BUP                 .

* general table data declarations..............
  INCLUDE LSVIMTDT                                .
