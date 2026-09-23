CLASS zjp_cl_p74_transport_script DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES zjp_if_outbound_transport.

    METHODS constructor
      IMPORTING
        scripted_response TYPE zjp_if_outbound_transport=>ty_response.

    METHODS get_post_count
      RETURNING VALUE(count) TYPE i.

  PRIVATE SECTION.

    DATA response_template
      TYPE zjp_if_outbound_transport=>ty_response.

    DATA post_count TYPE i.

ENDCLASS.


CLASS zjp_cl_p74_transport_script IMPLEMENTATION.

  METHOD constructor.

    response_template = scripted_response.
    post_count = 0.

  ENDMETHOD.


  METHOD zjp_if_outbound_transport~post.

    post_count = post_count + 1.

    response = response_template.

  ENDMETHOD.


  METHOD get_post_count.

    count = post_count.

  ENDMETHOD.

ENDCLASS.