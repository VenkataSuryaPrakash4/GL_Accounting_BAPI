*&---------------------------------------------------------------------*
*& Report ZR_F02_BAPI_POST
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zr_f02_bapi_post.

TYPES:BEGIN OF ty_excel,
        serial(5) TYPE c,
        h_txt     TYPE bktxt,
        com_code  TYPE t001-bukrs,
        doc_type  TYPE blart,
        ref_num   TYPE xblnr,
        gl_acc    TYPE hkont,
        itm_txt   TYPE sgtxt,
        pro_cnt   TYPE prctr,
        amnt      TYPE bapidoccur,
      END OF ty_excel.

DATA:lt_bdc        TYPE TABLE OF bdcdata,
     lt_excel      TYPE TABLE OF ty_excel,
     lt_msg        TYPE TABLE OF bdcmsgcoll,
     lt_gl         TYPE TABLE OF bapiacgl09,
     lt_curr       TYPE TABLE OF bapiaccr09,
     lt_return     TYPE TABLE OF bapiret2,
     lt_return_tmp TYPE TABLE OF bapiret2,
     w_raw         TYPE truxs_t_text_data,
     wa_head       TYPE bapiache09,
     lv_fname      TYPE rlgrap-filename,
     lv_monat      TYPE bkpf-monat,
     lv_item       TYPE posnr_acc,
     lv_budat      TYPE bkpf-budat,
     lv_date_Ext   TYPE char10,
     lv_amnt(132)  TYPE c,
     lv_filename   TYPE ibipparms-path.

*1. Selction screen to read the file from local computer
PARAMETERS:p_file TYPE dynpread-fieldname.

*  1.1 Enable F4 help to input field.
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.

* 1.2 Display pop up to choose the file from local computer.
  CALL FUNCTION 'F4_FILENAME'
    EXPORTING
      program_name  = syst-cprog
      dynpro_number = syst-dynnr
      field_name    = 'P_FILE'
    IMPORTING
      file_name     = lv_filename.
  IF sy-subrc = 0.
    p_file = lv_filename.
    lv_fname = lv_filename.
  ENDIF.

START-OF-SELECTION.
*2 Convert the excel file to internal tables
  CALL FUNCTION 'TEXT_CONVERT_XLS_TO_SAP'
    EXPORTING
      i_field_seperator    = 'X'
      i_line_header        = 'X'
      i_tab_raw_data       = w_raw
      i_filename           = lv_fname
    TABLES
      i_tab_converted_data = lt_excel
    EXCEPTIONS
      conversion_failed    = 1
      OTHERS               = 2.

  IF lt_excel IS NOT INITIAL.
    SELECT bukrs,waers
      FROM t001
      INTO TABLE @DATA(lt_t001)
      FOR ALL ENTRIES IN @lt_excel
      WHERE bukrs = @lt_excel-com_code.
    IF sy-subrc = 0.
      SORT lt_t001 BY bukrs.
    ENDIF.
  ENDIF.

  LOOP AT lt_excel INTO DATA(lwa_excel_tmp).
    DATA(lwa_excel) = lwa_excel_tmp.
    AT NEW serial.
      lv_budat = sy-datum.
*      CALL FUNCTION 'FI_PERIOD_DETERMINE'
*        EXPORTING
*          i_budat        = lv_budat
*          i_bukrs        = lwa_excel-com_code
*        IMPORTING
*          e_monat        = lv_monat
*        EXCEPTIONS
*          fiscal_year    = 1
*          period         = 2
*          period_version = 3
*          posting_period = 4
*          special_period = 5
*          version        = 6
*          posting_date   = 7
*          OTHERS         = 8.
*Header
      wa_head-username = sy-uname.
      wa_head-header_txt = lwa_excel-h_txt.
      wa_head-comp_code = lwa_excel-com_code.
      wa_head-doc_date = sy-datum.
      wa_head-pstng_date = sy-datum.
      wa_head-fis_period = 11.
      wa_head-doc_type = lwa_excel-doc_type.
      wa_head-ref_doc_no = lwa_excel-ref_num.
      DATA(lwa_t001) = lt_t001[ bukrs = lwa_excel-com_code ].
    ENDAT.

*GL Items
    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
      EXPORTING
        input  = lwa_excel-gl_acc
      IMPORTING
        output = lwa_excel-gl_acc.

    ADD 1 TO lv_item.
    APPEND VALUE #( itemno_acc = lv_item gl_account = lwa_excel-gl_acc
                    item_text = lwa_excel-itm_txt profit_ctr = lwa_excel-pro_cnt ) TO lt_gl.

*Currency for line items
    IF lv_item NE 1.
      lwa_excel-amnt = lwa_excel-amnt * -1.
    ENDIF.
    APPEND VALUE #( itemno_acc = lv_item currency = lwa_t001-waers
                    currency_iso = lwa_t001-waers amt_doccur = lwa_excel-amnt ) TO lt_curr.
    AT END OF serial.
*Call bapi for posting
      CALL FUNCTION 'BAPI_ACC_DOCUMENT_POST'
        EXPORTING
          documentheader = wa_head
        TABLES
          accountgl      = lt_gl
          currencyamount = lt_curr
          return         = lt_return_tmp.

      READ TABLE lt_return_tmp WITH KEY type = 'E'
                               TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        DELETE lt_return_tmp INDEX 1.
        else.
          CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
           EXPORTING
             WAIT          = 'X'
*           IMPORTING
*             RETURN        =
                    .

      ENDIF.
      APPEND LINES OF lt_return_tmp TO lt_return.
      CLEAR:wa_head,lt_gl,lt_curr,lt_return_tmp,lwa_t001,lv_item.
    ENDAT.

    CLEAR:lv_monat,lv_budat,lwa_excel_tmp,lwa_excel.
  ENDLOOP.
