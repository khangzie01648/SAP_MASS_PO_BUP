PROCESS BEFORE OUTPUT.
  MODULE status_0600.
  " Gọi subscreen area động dựa trên biến g_result_sub
  CALL SUBSCREEN g_result_sub INCLUDING sy-repid g_result_sub.

PROCESS AFTER INPUT.
  " Gọi lại subscreen để ghi nhận tương tác của người dùng
  CALL SUBSCREEN g_result_sub.
  MODULE user_command_0600.
