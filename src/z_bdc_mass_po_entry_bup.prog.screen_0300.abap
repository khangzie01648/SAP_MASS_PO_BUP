PROCESS BEFORE OUTPUT.
  MODULE status_0300.
  " Gọi tên khung G_SUB_DYNPRO trên layout để nhúng số màn hình chứa
"trong biến g_sub_dynpro
  CALL SUBSCREEN g_sub_dynpro INCLUDING sy-repid g_sub_dynpro.

PROCESS AFTER INPUT.
  " Bắt buộc gọi đúng tên khung G_SUB_DYNPRO ở đây để hứng sự kiện
  CALL SUBSCREEN g_sub_dynpro.
  MODULE user_command_0300.
