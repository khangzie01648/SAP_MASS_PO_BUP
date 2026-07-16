PROCESS BEFORE OUTPUT.
  MODULE status_0650.
  " Gọi subscreen hiển thị tĩnh 21 trường dữ liệu
  CALL SUBSCREEN sub_po_fields INCLUDING sy-repid '0651'.

PROCESS AFTER INPUT.
  CALL SUBSCREEN sub_po_fields.
  MODULE user_command_0650.
