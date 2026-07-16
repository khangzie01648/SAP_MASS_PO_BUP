PROCESS BEFORE OUTPUT.
  MODULE status_0550.
  " Gọi 2 subscreen chứa Header và Item
  CALL SUBSCREEN sub_header INCLUDING sy-repid '0551'.
  CALL SUBSCREEN sub_item INCLUDING sy-repid '0552'.

PROCESS AFTER INPUT.
  " Cho phép người dùng chỉnh sửa dữ liệu trên 2 tab
  CALL SUBSCREEN sub_header.
  CALL SUBSCREEN sub_item.
  MODULE user_command_0550.
