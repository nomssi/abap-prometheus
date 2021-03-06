CLASS zcl_prometheus DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE .

  PUBLIC SECTION.
    INTERFACES zif_prometheus.
    ALIASES read_all FOR zif_prometheus~read_all.
    ALIASES read_single FOR zif_prometheus~read_single.
    ALIASES write_single FOR zif_prometheus~write_single.
    ALIASES write_multiple FOR zif_prometheus~write_multiple.
    ALIASES delete FOR zif_prometheus~delete.
    ALIASES get_metric_string FOR zif_prometheus~get_metric_string.

    CLASS-DATA test_mode TYPE abap_bool VALUE abap_false.

    CLASS-METHODS:
      class_constructor,
      set_instance
        IMPORTING i_instance_name TYPE string OPTIONAL,
      set_instance_from_request
        IMPORTING i_request TYPE REF TO if_rest_request.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-DATA instance TYPE REF TO zcl_prometheus.

    DATA instance_name TYPE string.

    CLASS-METHODS:
      attach_for_update
        RETURNING VALUE(r_result) TYPE REF TO zcl_shr_prometheus_area
        RAISING
                  cx_shm_attach_error,
      attach_for_read
        RETURNING VALUE(r_result) TYPE REF TO zcl_shr_prometheus_area
        RAISING
                  cx_shm_attach_error,
      update_or_append
        IMPORTING
          i_modify_record TYPE zif_prometheus=>t_modify_record
        CHANGING
          c_data          TYPE zif_prometheus=>t_record_table,
      detach
        IMPORTING
          i_shr_area TYPE REF TO zcl_shr_prometheus_area
        RAISING
          cx_shm_already_detached
          cx_shm_completion_error
          cx_shm_secondary_commit
          cx_shm_wrong_handle.
ENDCLASS.



CLASS ZCL_PROMETHEUS IMPLEMENTATION.


  METHOD attach_for_read.
    TRY.
        r_result = zcl_shr_prometheus_area=>attach_for_read( inst_name = CONV #( instance->instance_name ) ).
      CATCH cx_shm_no_active_version.
        WAIT UP TO 1 SECONDS.
        r_result = zcl_shr_prometheus_area=>attach_for_read( inst_name = CONV #( instance->instance_name ) ).
    ENDTRY.
  ENDMETHOD.


  METHOD attach_for_update.
    TRY.
        r_result = zcl_shr_prometheus_area=>attach_for_update( inst_name = CONV #( instance->instance_name ) ).
      CATCH cx_shm_no_active_version.
        WAIT UP TO 1 SECONDS.
        r_result = zcl_shr_prometheus_area=>attach_for_update( inst_name = CONV #( instance->instance_name ) ).
    ENDTRY.
  ENDMETHOD.


  METHOD class_constructor.
    instance = NEW #( ).
  ENDMETHOD.


  METHOD detach.
    IF test_mode = abap_true.
      i_shr_area->detach_rollback( ).
    ELSE.
      i_shr_area->detach_commit( ).
    ENDIF.
  ENDMETHOD.


  METHOD set_instance.
    instance->instance_name = COND #( WHEN i_instance_name IS INITIAL THEN cl_shm_area=>default_instance
                                                                      ELSE i_instance_name ).
  ENDMETHOD.


  METHOD set_instance_from_request.
    instance->instance_name = cl_shm_area=>default_instance.

    CHECK i_request IS BOUND.
    instance->instance_name = i_request->get_uri_attribute( 'instance' ).

    CHECK instance->instance_name IS INITIAL.
    instance->instance_name = i_request->get_uri_query_parameter( 'instance' ).

    CHECK instance->instance_name IS INITIAL.
    DATA(segments) = i_request->get_uri_segments( ).
    instance->instance_name = to_upper( segments[ 1 ] ).
  ENDMETHOD.


  METHOD update_or_append.
    TRY.
        DATA(key) = to_lower( i_modify_record-key ).
        DATA(value) = condense( i_modify_record-value ).

        ASSIGN c_data[ key = key ] TO FIELD-SYMBOL(<record>).
        IF sy-subrc EQ 0.  " line exists

          IF i_modify_record-command EQ zif_prometheus=>c_command-increment.
            value = <record>-value + value.
            value = condense( value ).
          ENDIF.

          <record>-value = value.
        ELSE.

          APPEND VALUE #( key = key
                          value = SWITCH #( i_modify_record-command
                                       WHEN zif_prometheus=>c_command-increment THEN '1'
                                       ELSE value )  ) TO c_data.
          SORT c_data BY key.
        ENDIF.

      CATCH cx_root.
        RETURN.
    ENDTRY.

  ENDMETHOD.


  METHOD zif_prometheus~delete.
    DATA(shr_area) = attach_for_update( ).
    DATA(shr_root) = CAST zcl_shr_prometheus_root( shr_area->get_root( ) ).

    DATA(key) = to_lower( i_key ).
    IF line_exists( shr_root->data[ key = key ] ).
      DELETE shr_root->data WHERE key = key.
    ENDIF.

    shr_area->detach_commit( ).
  ENDMETHOD.


  METHOD zif_prometheus~get_metric_string.
    r_result = REDUCE #( INIT res TYPE string FOR record IN read_all( )
                         NEXT res = res && |{ record-key } { record-value }\r\n| ).
  ENDMETHOD.


  METHOD zif_prometheus~read_all.
    DATA(shr_area) = attach_for_read( ).
    r_result = shr_area->root->data.
    shr_area->detach( ).
  ENDMETHOD.


  METHOD zif_prometheus~read_single.
    DATA(shr_area) = attach_for_read( ).
    DATA(key) = to_lower( i_key ).

    IF line_exists( shr_area->root->data[ key = key ] ).
      r_result = shr_area->root->data[ key = key ]-value.
    ENDIF.
    shr_area->detach( ).
  ENDMETHOD.


  METHOD zif_prometheus~write_multiple.
    DATA(shr_area) = attach_for_update( ).
    DATA(shr_root) = CAST zcl_shr_prometheus_root( shr_area->get_root( ) ).

    LOOP AT i_record_table ASSIGNING FIELD-SYMBOL(<record>).
      update_or_append( EXPORTING i_modify_record = <record>
                        CHANGING c_data = shr_root->data ).
    ENDLOOP.

    detach( shr_area ).
  ENDMETHOD.


  METHOD zif_prometheus~write_single.
    DATA(shr_area) = attach_for_update( ).
    DATA(shr_root) = CAST zcl_shr_prometheus_root( shr_area->get_root( ) ).

    update_or_append( EXPORTING i_modify_record = i_record
                      CHANGING c_data = shr_root->data ).
    detach( shr_area ).
  ENDMETHOD.
ENDCLASS.
