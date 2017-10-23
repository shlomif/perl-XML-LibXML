/* $Id$
 *
 * This is free software, you may use it and distribute it under the same terms as
 * Perl itself.
 *
 * Copyright 2001-2003 AxKit.com Ltd., 2002-2006 Christian Glahn, 2006-2009 Petr Pajas
*/

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_MSC_VER)
#define _CRT_SECURE_NO_DEPRECATE 1
#define _CRT_NONSTDC_NO_DEPRECATE 1
#endif

/* perl stuff */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#define NEED_newRV_noinc_GLOBAL
#define NEED_sv_2pv_flags
#include "ppport.h"
#include "Av_CharPtrPtr.h"  /* XS_*_charPtrPtr() */

#include <fcntl.h>

#ifndef WIN32
#include <unistd.h>
#endif

/* libxml2 configuration properties */
#include <libxml/xmlversion.h>

#define DEBUG_C14N

/* libxml2 stuff */
#include <libxml/xmlversion.h>
#include <libxml/globals.h>
#include <libxml/xmlmemory.h>
#include <libxml/parser.h>
#include <libxml/parserInternals.h>
#include <libxml/HTMLparser.h>
#include <libxml/HTMLtree.h>
#include <libxml/c14n.h>
#include <libxml/tree.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>
#include <libxml/xmlIO.h>
/* #include <libxml/debugXML.h> */
#include <libxml/xmlerror.h>
#include <libxml/xinclude.h>
#include <libxml/valid.h>

#ifdef LIBXML_PATTERN_ENABLED
#include <libxml/pattern.h>
#endif

#ifdef LIBXML_REGEXP_ENABLED
#include <libxml/xmlregexp.h>
#endif

#if LIBXML_VERSION >= 20510
#define HAVE_SCHEMAS
#include <libxml/relaxng.h>
#include <libxml/xmlschemas.h>
#endif

#if LIBXML_VERSION >= 20621
#define WITH_SERRORS
#ifdef LIBXML_READER_ENABLED
#define HAVE_READER_SUPPORT
#include <libxml/xmlreader.h>
#endif
#endif

#ifdef LIBXML_CATALOG_ENABLED
#include <libxml/catalog.h>
#endif

#ifdef HAVE_READER_SUPPORT

typedef enum {
    XML_TEXTREADER_NONE = -1,
    XML_TEXTREADER_START= 0,
    XML_TEXTREADER_ELEMENT= 1,
    XML_TEXTREADER_END= 2,
    XML_TEXTREADER_EMPTY= 3,
    XML_TEXTREADER_BACKTRACK= 4,
    XML_TEXTREADER_DONE= 5,
    XML_TEXTREADER_ERROR= 6
} xmlTextReaderState;

typedef enum {
    XML_TEXTREADER_NOT_VALIDATE = 0,
    XML_TEXTREADER_VALIDATE_DTD = 1,
    XML_TEXTREADER_VALIDATE_RNG = 2,
    XML_TEXTREADER_VALIDATE_XSD = 4
} xmlTextReaderValidate;

#endif /* HAVE_READER_SUPPORT */

/* GDOME support
 * libgdome installs only the core functions to the system.
 * this is not enough for XML::LibXML <-> XML::GDOME conversion.
 * therefore there is the need to ship as well the GDOME core headers.
 */
#ifdef XML_LIBXML_GDOME_SUPPORT

#include <libgdome/gdome.h>
#include <libgdome/gdome-libxml-util.h>

#endif


#if LIBXML_VERSION < 20621
/* HTML_PARSE_RECOVER was added in libxml2 2.6.21 */
#  define HTML_PARSE_RECOVER XML_PARSE_RECOVER
#endif


/* XML::LibXML stuff */
#include "perl-libxml-mm.h"
#include "perl-libxml-sax.h"

#include "dom.h"
#include "xpath.h"
#include "xpathcontext.h"

#ifdef __cplusplus
}
#endif


#define TEST_PERL_FLAG(flag) \
    SvTRUE(get_sv(flag, FALSE)) ? 1 : 0

#ifdef HAVE_READER_SUPPORT
#define LIBXML_READER_TEST_ELEMENT(reader,name,nsURI) \
  (xmlTextReaderNodeType(reader) == XML_READER_TYPE_ELEMENT) &&	\
   ((!nsURI && !name) \
    || \
    (!nsURI && xmlStrcmp((const xmlChar*)name, xmlTextReaderConstName(reader) ) == 0 ) \
    || \
    (nsURI && xmlStrcmp((const xmlChar*)nsURI, xmlTextReaderConstNamespaceUri(reader))==0 \
     && \
     (!name || xmlStrcmp((const xmlChar*)name, xmlTextReaderConstLocalName(reader)) == 0)))
#endif

/* this should keep the default */
static xmlExternalEntityLoader LibXML_old_ext_ent_loader = NULL;

/* global external entity loader */
SV *EXTERNAL_ENTITY_LOADER_FUNC = (SV *)NULL;

SV* PROXY_NODE_REGISTRY_MUTEX = NULL;

/* ****************************************************************
 * Error handler
 * **************************************************************** */

#ifdef WITH_SERRORS

#define INIT_READER_ERROR_HANDLER(reader)

#define PREINIT_SAVED_ERROR   SV* saved_error = sv_2mortal(newSV(0));

#define INIT_ERROR_HANDLER                                                      \
     xmlSetGenericErrorFunc((void *)saved_error,                                \
			    (xmlGenericErrorFunc) LibXML_flat_handler);         \
     xmlSetStructuredErrorFunc((void *)saved_error,			        \
			    (xmlStructuredErrorFunc)LibXML_struct_error_handler)

#define REPORT_ERROR(recover) LibXML_report_error_ctx(saved_error, recover)

#define CLEANUP_ERROR_HANDLER  xmlSetGenericErrorFunc(NULL,NULL); \
                               xmlSetStructuredErrorFunc(NULL,NULL)

#else /* WITH_SERRORS */

#define INIT_READER_ERROR_HANDLER(reader)                                 \
  if (reader)                                                             \
    xmlTextReaderSetErrorHandler(reader, LibXML_reader_error_handler,     \
                                 sv_2mortal(newSVpv("",0)));

#define PREINIT_SAVED_ERROR  SV* saved_error = sv_2mortal(newSVpv("",0));

#define INIT_ERROR_HANDLER                                                \
    xmlSetGenericErrorFunc((void *) saved_error,                          \
                           (xmlGenericErrorFunc) LibXML_error_handler_ctx)

#define REPORT_ERROR(recover) LibXML_report_error_ctx(saved_error, recover)

#define CLEANUP_ERROR_HANDLER xmlSetGenericErrorFunc(NULL,NULL);


#endif  /* WITH_SERRORS */

#ifdef WITH_SERRORS
void
LibXML_struct_error_callback(SV * saved_error, SV * libErr )
{

    dTHX;
    dSP;

    if ( saved_error == NULL ) {
        warn( "have no save_error\n" );
    }

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    XPUSHs(sv_2mortal(libErr));
    if ( saved_error != NULL && SvOK(saved_error) ) {
        XPUSHs(saved_error);
    }
    PUTBACK;

    if ( saved_error != NULL ) {
      call_pv( "XML::LibXML::Error::_callback_error", G_SCALAR | G_EVAL );
    } else {
      call_pv( "XML::LibXML::Error::_instant_error_callback", G_SCALAR );
    }
    SPAGAIN;

    if ( SvTRUE(ERRSV) ) {
      (void) POPs;
      croak_obj;
    } else {
      sv_setsv(saved_error, POPs);
    }

    PUTBACK;
    FREETMPS;
    LEAVE;
}

void
LibXML_struct_error_handler(SV * saved_error, xmlErrorPtr error )
{
    const char * CLASS = "XML::LibXML::LibError";
    SV* libErr;

    libErr = NEWSV(0,0);
    sv_setref_pv( libErr, CLASS, (void*)error );
    LibXML_struct_error_callback( saved_error, libErr);
}


void
LibXML_flat_handler(SV * saved_error, const char * msg, ...)
{
    SV* sv;
    va_list args;

    sv = newSVpv("",0);
    va_start(args, msg);
    sv_vcatpvf(sv, msg, &args);
    va_end(args);
    xs_warn("flat error\n");
    LibXML_struct_error_callback( saved_error, sv);
}

#endif /* WITH_SERRORS */


/* If threads-support is working correctly in libxml2 then
 * this method will be called with the correct thread-context */
void
LibXML_error_handler_ctx(void * ctxt, const char * msg, ...)
{
	va_list args;
	SV * saved_error = (SV *) ctxt;

	/* If saved_error is null we croak with the error */
	if( NULL == saved_error ) {
		SV * sv = sv_2mortal(newSV(0));
		va_start(args, msg);
                /* vfprintf(stderr, msg, args); */
   		sv_vsetpvfn(sv, msg, strlen(msg), &args, NULL, 0, NULL);
   		va_end(args);
		croak("%s", SvPV_nolen(sv));
	/* Otherwise, save the error */
	} else {
		va_start(args, msg);
                /* vfprintf(stderr, msg, args);	*/
   		sv_vcatpvfn(saved_error, msg, strlen(msg), &args, NULL, 0, NULL);
		va_end(args);
	}
}

static void
LibXML_validity_error_ctx(void * ctxt, const char *msg, ...)
{
	va_list args;
	SV * saved_error = (SV *) ctxt;

	/* If saved_error is null we croak with the error */
	if( NULL == saved_error ) {
		SV * sv = sv_2mortal(newSV(0));
		va_start(args, msg);
   		sv_vsetpvfn(sv, msg, strlen(msg), &args, NULL, 0, NULL);
   		va_end(args);
		croak("%s", SvPV_nolen(sv));
	/* Otherwise, save the error */
	} else {
		va_start(args, msg);
   		sv_vcatpvfn(saved_error, msg, strlen(msg), &args, NULL, 0, NULL);
		va_end(args);
	}
}

static void
LibXML_validity_warning_ctx(void * ctxt, const char *msg, ...)
{
	va_list args;
	SV * saved_error = (SV *) ctxt;
	STRLEN len;

	/* If saved_error is null we croak with the error */
	if( NULL == saved_error ) {
		SV * sv = sv_2mortal(newSV(0));
		va_start(args, msg);
   		sv_vsetpvfn(sv, msg, strlen(msg), &args, NULL, 0, NULL);
   		va_end(args);
		croak("LibXML_validity_warning_ctx internal error: context was null (%s)", SvPV_nolen(sv));
	/* Otherwise, give the warning */
	} else {
		va_start(args, msg);
   		sv_vcatpvfn(saved_error, msg, strlen(msg), &args, NULL, 0, NULL);
		va_end(args);
		warn("validation error: %s", SvPV(saved_error, len));
	}
}

static int
LibXML_will_die_ctx(SV * saved_error, int recover)
{
#ifdef WITH_SERRORS
    if( saved_error!=NULL && SvOK(saved_error) ) {
	if ( recover == 0 ) {
	  return 1;
	}
    }
#else
    if( 0 < SvCUR( saved_error ) ) {
	if ( recover == 0 ) {
	    return 1;
	}
    }
#endif
    return 0;
}


static void
LibXML_report_error_ctx(SV * saved_error, int recover)
{
#ifdef WITH_SERRORS
  if( saved_error!=NULL && SvOK( saved_error ) ) {
    if (!recover || recover==1) {
      dTHX;
      dSP;

      ENTER;
      SAVETMPS;
      PUSHMARK(SP);
      EXTEND(SP, 1);
      PUSHs(saved_error);
      PUTBACK;
      if (recover==1) {
	call_pv( "XML::LibXML::Error::_report_warning", G_SCALAR | G_DISCARD);
      } else {
	call_pv( "XML::LibXML::Error::_report_error", G_SCALAR | G_DISCARD);
      }
      SPAGAIN;

      PUTBACK;
      FREETMPS;
      LEAVE;
    }
  }
#else
    if( 0 < SvCUR( saved_error ) ) {
	if( recover ) {
	    if ( recover == 1 ) {
		warn("%s", SvPV_nolen(saved_error));
	    } /* else recover silently */
	} else {
	    croak("%s", SvPV_nolen(saved_error));
	}
    }
#endif
}

#ifdef HAVE_READER_SUPPORT

#ifndef WITH_SERRORS
static void
LibXML_reader_error_handler(void * ctxt,
				const char * msg,
				xmlParserSeverities severity,
				xmlTextReaderLocatorPtr locator)
{
  int line = xmlTextReaderLocatorLineNumber(locator);
  xmlChar * filename = xmlTextReaderLocatorBaseURI(locator);
  SV * msg_sv = sv_2mortal(C2Sv((xmlChar*) msg,NULL));
  SV * error = sv_2mortal(newSVpv("", 0));

  switch (severity) {
  case XML_PARSER_SEVERITY_VALIDITY_WARNING:
    sv_catpv(error, "Validity WARNING");
    break;
  case XML_PARSER_SEVERITY_WARNING:
    sv_catpv(error, "Reader WARNING");
    break;
  case XML_PARSER_SEVERITY_VALIDITY_ERROR:
    sv_catpv(error, "Validity ERROR");
    break;
  case XML_PARSER_SEVERITY_ERROR:
    sv_catpv(error, "Reader ERROR");
    break;
  }
  if (filename) {
    sv_catpvf(error, " in %s", filename);
    xmlFree(filename);
  }
  if (line >= 0) {
    sv_catpvf(error, " at line %d", line);
  }
  sv_catpvf(error, ": %s", SvPV_nolen(msg_sv));
  if (severity == XML_PARSER_SEVERITY_VALIDITY_WARNING ||
      severity == XML_PARSER_SEVERITY_WARNING ) {
    warn("%s", SvPV_nolen(error));
  } else {
    SV * error_sv = (SV*) ctxt;
    if (error_sv) {
      sv_catpvf(error_sv, "%s  ", SvPV_nolen(error));
    } else {
      croak("%s",SvPV_nolen(error));
    }
  }
}
#endif /* !defined WITH_SERRORS */

SV *
LibXML_get_reader_error_data(xmlTextReaderPtr reader)
{
  SV * saved_error = NULL;
  xmlTextReaderErrorFunc f = NULL;
  xmlTextReaderGetErrorHandler(reader, &f, (void **) &saved_error);
  return saved_error;
}

#ifndef WITH_SERRORS
static void
LibXML_report_reader_error(xmlTextReaderPtr reader)
{
  SV * saved_error = NULL;
  xmlTextReaderErrorFunc f = NULL;
  xmlTextReaderGetErrorHandler(reader, &f, (void **) &saved_error);
  if ( saved_error && SvOK( saved_error) && 0 < SvCUR( saved_error ) ) {
    croak("%s", SvPV_nolen(saved_error));
  }
}
#endif /* !defined WITH_SERRORS */

#endif /* HAVE_READER_SUPPORT */

static int
LibXML_get_recover(HV * real_obj)
{
    SV** item = hv_fetch( real_obj, "XML_LIBXML_RECOVER", 18, 0 );
    return ( item != NULL && SvTRUE(*item) ) ? SvIV(*item) : 0;
}

static SV *
LibXML_NodeToSv(HV * real_obj, xmlNodePtr real_doc)
{
    SV** item = hv_fetch( real_obj, "XML_LIBXML_GDOME", 16, 0 );

    if ( item != NULL && SvTRUE(*item) ) {
        return PmmNodeToGdomeSv(real_doc);
    }
    else {
        return PmmNodeToSv(real_doc, NULL);
    }
}

/* ****************************************************************
 * IO callbacks
 * **************************************************************** */

int
LibXML_read_perl (SV * ioref, char * buffer, int len)
{
    dTHX;
    dSP;

    int cnt;
    SV * read_results;
    IV read_results_iv;
    STRLEN read_length;
    char * chars;
    SV * tbuff = NEWSV(0,len);
    SV * tsize = newSViv(len);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 3);
    PUSHs(ioref);
    PUSHs(sv_2mortal(tbuff));
    PUSHs(sv_2mortal(tsize));
    PUTBACK;

    if (sv_isobject(ioref)) {
        cnt = call_method("read", G_SCALAR | G_EVAL);
    }
    else {
        cnt = call_pv("XML::LibXML::__read", G_SCALAR | G_EVAL);
    }

    SPAGAIN;

    if (cnt != 1) {
        croak("read method call failed");
    }

    if (SvTRUE(ERRSV)) {
       (void) POPs;
       croak_obj;
    }

    read_results = POPs;

    if (!SvOK(read_results)) {
        croak("read error");
    }

    read_results_iv = SvIV(read_results);

    chars = SvPV(tbuff, read_length);

    /*
     * If the file handle uses an encoding layer, the length parameter is
     * interpreted as character count, not as byte count. So it's possible
     * that more than len bytes are read which would overflow the buffer.
     * Check for this condition also by comparing the return value.
     */
    if (read_results_iv != read_length || read_length > len) {
        croak("Read more bytes than requested. Do you use an encoding-related"
              " PerlIO layer?");
    }
    strncpy(buffer, chars, read_length);

    PUTBACK;
    FREETMPS;
    LEAVE;

    return read_length;
}

/* used only by Reader */
int
LibXML_close_perl (SV * ioref)
{
  SvREFCNT_dec(ioref);
  return 0;
}

int
LibXML_input_match(char const * filename)
{
    int results;
    int count;
    SV * res;

    results = 0;

    {
        dTHX;
        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 1);
        PUSHs(sv_2mortal(newSVpv((char*)filename, 0)));
        PUTBACK;

        count = call_pv("XML::LibXML::InputCallback::_callback_match",
                             G_SCALAR | G_EVAL);

        SPAGAIN;

        if (count != 1) {
            croak("match callback must return a single value");
        }

        if (SvTRUE(ERRSV)) {
            (void) POPs;
            croak_obj;
        }

        res = POPs;

        if (SvTRUE(res)) {
            results = 1;
        }

        PUTBACK;
        FREETMPS;
        LEAVE;
    }
    return results;
}

void *
LibXML_input_open(char const * filename)
{
    SV * results;
    int count;

    dTHX;
    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    EXTEND(SP, 1);
    PUSHs(sv_2mortal(newSVpv((char*)filename, 0)));
    PUTBACK;

    count = call_pv("XML::LibXML::InputCallback::_callback_open",
                              G_SCALAR | G_EVAL);

    SPAGAIN;

    if (count != 1) {
        croak("open callback must return a single value");
    }

    if (SvTRUE(ERRSV)) {
        (void) POPs;
        croak_obj;
    }

    results = POPs;

    (void)SvREFCNT_inc(results);

    PUTBACK;
    FREETMPS;
    LEAVE;

    return (void *)results;
}

int
LibXML_input_read(void * context, char * buffer, int len)
{
    STRLEN res_len;
    const char * output;
    SV * ctxt;
    SV * output_sv;

    res_len = 0;
    ctxt = (SV *)context;

    {
        int count;

        dTHX;
        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 2);
        PUSHs(ctxt);
        PUSHs(sv_2mortal(newSViv(len)));
        PUTBACK;

        count = call_pv("XML::LibXML::InputCallback::_callback_read",
                             G_SCALAR | G_EVAL);

        SPAGAIN;

        if (count != 1) {
            croak("read callback must return a single value");
        }

        if (SvTRUE(ERRSV)) {
            (void) POPs;
            croak_obj;
        }

        /*
         * Handle undef()s gracefully, to avoid using POPpx which warns upon $^W
         * being set. See t/49callbacks_returning_undef.t and:
         * https://rt.cpan.org/Ticket/Display.html?id=70321
         * */

        output_sv = POPs;
        output = SvOK(output_sv) ? SvPV_nolen(output_sv) : NULL;

        if (output != NULL) {
            res_len = strlen(output);
            if (res_len) {
                strncpy(buffer, output, res_len);
            }
            else {
                buffer[0] = 0;
            }
        }

	PUTBACK;
        FREETMPS;
        LEAVE;
    }
    return res_len;
}

void
LibXML_input_close(void * context)
{
    SV * ctxt;

    ctxt = (SV *)context;

    {
        dTHX;
        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 1);
        PUSHs(ctxt);
        PUTBACK;

        call_pv("XML::LibXML::InputCallback::_callback_close",
                             G_SCALAR | G_EVAL | G_DISCARD);

        SvREFCNT_dec(ctxt);

        if (SvTRUE(ERRSV)) {
            croak_obj;
        }

        FREETMPS;
        LEAVE;
    }
}

int
LibXML_output_write_handler(void * ioref, char * buffer, int len)
{
    if ( buffer != NULL && len > 0) {
        dTHX;
        dSP;

        SV * tbuff = newSVpv(buffer,len);
        SV * tsize = newSViv(len);


        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 3);
        PUSHs((SV*)ioref);
        PUSHs(sv_2mortal(tbuff));
        PUSHs(sv_2mortal(tsize));
        PUTBACK;

        call_pv("XML::LibXML::__write", G_SCALAR | G_EVAL | G_DISCARD );

        if (SvTRUE(ERRSV)) {
            croak_obj;
        }

        FREETMPS;
        LEAVE;
    }
    return len;
}

int
LibXML_output_close_handler( void * handler )
{
    return 1;
}

xmlParserInputPtr
LibXML_load_external_entity(
        const char * URL,
        const char * ID,
        xmlParserCtxtPtr ctxt)
{
    SV ** func;
    int count;
    SV * results;
    STRLEN results_len;
    const char * results_pv;
    xmlParserInputBufferPtr input_buf;

    if (ctxt->_private == NULL && EXTERNAL_ENTITY_LOADER_FUNC == NULL)
    {
        return xmlNewInputFromFile(ctxt, URL);
    }

    if (URL == NULL) {
        URL = "";
    }
    if (ID == NULL) {
        ID = "";
    }

    /* fetch entity loader function */
    if(EXTERNAL_ENTITY_LOADER_FUNC != NULL)
    {
       func = &EXTERNAL_ENTITY_LOADER_FUNC;
    }
    else
    {
       SV * self;
       HV * real_obj;

       self = (SV *)ctxt->_private;
       real_obj = (HV *)SvRV(self);
       func = hv_fetch(real_obj, "ext_ent_handler", 15, 0);
    }

    if (func != NULL && SvTRUE(*func)) {
        dTHX;
        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;
        XPUSHs(sv_2mortal(newSVpv((char*)URL, 0)));
        XPUSHs(sv_2mortal(newSVpv((char*)ID, 0)));
        PUTBACK;

        count = call_sv(*func, G_SCALAR | G_EVAL);

        SPAGAIN;

        if (count == 0) {
            croak("external entity handler did not return a value");
        }

        if (SvTRUE(ERRSV)) {
            (void) POPs;
            croak_obj;
        }

        results = POPs;

        results_pv = SvPV(results, results_len);
        input_buf = xmlParserInputBufferCreateMem(
                        results_pv,
                        results_len,
                        XML_CHAR_ENCODING_NONE
                        );

        PUTBACK;
        FREETMPS;
        LEAVE;

        return xmlNewIOInputStream(ctxt, input_buf, XML_CHAR_ENCODING_NONE);
    }
    else {
        if (URL == NULL) {
            return NULL;
        }
        return xmlNewInputFromFile(ctxt, URL);
    }
}

/* ****************************************************************
 * Helper functions
 * **************************************************************** */

HV*
LibXML_init_parser( SV * self, xmlParserCtxtPtr ctxt ) {
    /* we fetch all switches and callbacks from the hash */
    HV* real_obj = NULL;
    SV** item    = NULL;
    int parserOptions = XML_PARSE_NODICT;

    /* A NOTE ABOUT xmlInitParser();                     */
    /* xmlInitParser() should be used only at startup and*/
    /* not for initializing a single parser. libxml2's   */
    /* documentation is quite clear about this. If       */
    /* something fails it is a problem elsewhere. Simply */
    /* resetting the entire module will lead to unwanted */
    /* results in server environments, such as if        */
    /* mod_perl is used together with php's xml module.  */
    /* calling xmlInitParser() here is definitely wrong!  */
    /* xmlInitParser(); */

#ifndef WITH_SERRORS
    xmlGetWarningsDefaultValue = 0;
#endif
    if ( self != NULL ) {
        /* first fetch the values from the hash */
        real_obj = (HV *)SvRV(self);

        item = hv_fetch( real_obj, "XML_LIBXML_PARSER_OPTIONS", 25, 0 );
        if (item != NULL && SvOK(*item)) parserOptions = sv_2iv(*item);

        /* compatibility with old implementation:
           absence of XML_PARSE_DTDLOAD (load_ext_dtd) implies absence of
           all DTD related flags
         */
        if ((parserOptions & XML_PARSE_DTDLOAD) == 0) {
            parserOptions &= ~(XML_PARSE_DTDVALID | XML_PARSE_DTDATTR | XML_PARSE_NOENT );
        }
        if (ctxt) xmlCtxtUseOptions(ctxt, parserOptions ); /* Note: sets ctxt->linenumbers = 1 */

        /*
         * Without this if/else conditional, NOBLANKS has no effect.
         *
         * For more information, see:
         *
         * https://rt.cpan.org/Ticket/Display.html?id=76696
         *
         * */
        if (parserOptions & XML_PARSE_NOBLANKS) {
            xmlKeepBlanksDefault(0);
        }
        else {
            xmlKeepBlanksDefault(1);
        }

        item =  hv_fetch( real_obj, "XML_LIBXML_LINENUMBERS", 22, 0 );
        if ( item != NULL && SvTRUE(*item) ) {
            if (ctxt) ctxt->linenumbers = 1;
        }
        else {
            if (ctxt) ctxt->linenumbers = 0;
        }

       if(EXTERNAL_ENTITY_LOADER_FUNC == NULL)
       {
            item = hv_fetch(real_obj, "ext_ent_handler", 15, 0);
            if (item != NULL  && SvTRUE(*item)) {
                LibXML_old_ext_ent_loader =  xmlGetExternalEntityLoader();
                xmlSetExternalEntityLoader( (xmlExternalEntityLoader)LibXML_load_external_entity );
            }
            else
             {
                if (parserOptions & XML_PARSE_NONET)
                {
                    LibXML_old_ext_ent_loader = xmlGetExternalEntityLoader();
                    xmlSetExternalEntityLoader( xmlNoNetExternalEntityLoader );
                }
                /* LibXML_old_ext_ent_loader =  NULL; */
            }
       }
    }

    return real_obj;
}

void
LibXML_cleanup_parser() {
#ifndef WITH_SERRORS
    xmlGetWarningsDefaultValue = 0;
#endif
    if (EXTERNAL_ENTITY_LOADER_FUNC == NULL && LibXML_old_ext_ent_loader != NULL)
    {
        xmlSetExternalEntityLoader( (xmlExternalEntityLoader)LibXML_old_ext_ent_loader );
    }
}

int
LibXML_test_node_name( xmlChar * name )
{
    xmlChar * cur = name;
    int tc  = 0;
    int len = 0;

    if ( cur == NULL || *cur == 0 ) {
        /* warn("name is empty" ); */
        return(0);
    }

    tc = domParseChar( cur, &len );

    if ( !( IS_LETTER( tc ) || (tc == '_') || (tc == ':')) ) {
        /* warn( "is not a letter\n" ); */
        return(0);
    }

    tc  =  0;
    cur += len;

    while (*cur != 0 ) {
        tc = domParseChar( cur, &len );

        if (!(IS_LETTER(tc) || IS_DIGIT(tc) || (tc == '_') ||
             (tc == '-') || (tc == ':') || (tc == '.') ||
             IS_COMBINING(tc) || IS_EXTENDER(tc)) ) {
            /* warn( "is not a letter\n" ); */
            return(0);
        }
        tc = 0;
        cur += len;
    }

    /* warn("name is ok"); */
    return(1);
}

/* Assumes that the node has a proxy. */
static void
LibXML_reparent_removed_node(xmlNodePtr node) {
    /*
     * Attribute nodes can't be added to document fragments. Adding
     * DTD nodes would cause a memory leak.
     */
    if (node->type != XML_ATTRIBUTE_NODE
        && node->type != XML_DTD_NODE) {
        ProxyNodePtr docfrag = PmmNewFragment(node->doc);
        xmlAddChild(PmmNODE(docfrag), node);
        PmmFixOwner(PmmPROXYNODE(node), docfrag);
    }
}

static void
LibXML_set_int_subset(xmlDocPtr doc, xmlNodePtr dtd) {
    xmlNodePtr old_dtd = (xmlNodePtr)doc->intSubset;
    if (old_dtd == dtd) {
        return;
    }

    if (old_dtd != NULL) {
        xmlUnlinkNode(old_dtd);

        if (PmmPROXYNODE(old_dtd) == NULL) {
            xmlFreeDtd((xmlDtdPtr)old_dtd);
        }
    }

    doc->intSubset = (xmlDtdPtr)dtd;
}

/* ****************************************************************
 * XPathContext helper functions
 * **************************************************************** */

/* Temporary node pool:                                              *
 * Stores pnode in context node-pool hash table in order to preserve *
 * at least one reference.                                           *
 * If pnode is NULL, only return current value for hashkey           */
static SV*
LibXML_XPathContext_pool ( xmlXPathContextPtr ctxt, void * hashkey, SV * pnode ) {
    SV ** value;
    SV * key;
    STRLEN len;
    char * strkey;
    dTHX;

    if (XPathContextDATA(ctxt)->pool == NULL) {
        if (pnode == NULL) {
            return &PL_sv_undef;
        } else {
            xs_warn("initializing node pool");
            XPathContextDATA(ctxt)->pool = newHV();
        }
    }

    key = newSViv(PTR2IV(hashkey));
    strkey = SvPV(key, len);
    if (pnode != NULL && !hv_exists(XPathContextDATA(ctxt)->pool,strkey,len)) {
        value = hv_store(XPathContextDATA(ctxt)->pool,strkey,len, SvREFCNT_inc(pnode),0);
    } else {
        value = hv_fetch(XPathContextDATA(ctxt)->pool,strkey,len, 0);
    }
    SvREFCNT_dec(key);

    if (value == NULL) {
        return &PL_sv_undef;
    } else {
        return *value;
    }
}

/* convert perl result structures to LibXML structures */
static xmlXPathObjectPtr
LibXML_perldata_to_LibXMLdata(xmlXPathParserContextPtr ctxt,
                              SV* perl_result) {
    dTHX;

    if (!SvOK(perl_result)) {
        return (xmlXPathObjectPtr)xmlXPathNewCString("");
    }
    if (SvROK(perl_result) &&
        SvTYPE(SvRV(perl_result)) == SVt_PVAV) {
        /* consider any array ref to be a nodelist */
        int i;
        int length;
        SV ** pnode;
        AV * array_result;
        xmlXPathObjectPtr ret;

        ret = (xmlXPathObjectPtr) xmlXPathNewNodeSet(INT2PTR(xmlNodePtr,NULL));
        array_result = (AV*)SvRV(perl_result);
        length = av_len(array_result);
        for( i = 0; i <= length ; i++ ) {
            pnode = av_fetch(array_result,i,0);
            if (pnode != NULL && sv_isobject(*pnode) &&
                sv_derived_from(*pnode,"XML::LibXML::Node")) {
                xmlXPathNodeSetAdd(ret->nodesetval,
                                   INT2PTR(xmlNodePtr,PmmSvNode(*pnode)));
                if(ctxt) {
                    LibXML_XPathContext_pool(ctxt->context,
                                             PmmSvNode(*pnode), *pnode);
                }
            } else {
                warn("XPathContext: ignoring non-node member of a nodelist");
            }
        }
        return ret;
    } else if (sv_isobject(perl_result) &&
               (SvTYPE(SvRV(perl_result)) == SVt_PVMG))
        {
            if (sv_derived_from(perl_result, "XML::LibXML::Node")) {
                xmlNodePtr tmp_node;
                xmlXPathObjectPtr ret;

                ret =  INT2PTR(xmlXPathObjectPtr,xmlXPathNewNodeSet(NULL));
                tmp_node = INT2PTR(xmlNodePtr,PmmSvNode(perl_result));
                xmlXPathNodeSetAdd(ret->nodesetval,tmp_node);
                if(ctxt) {
                    LibXML_XPathContext_pool(ctxt->context, PmmSvNode(perl_result),
                                             perl_result);
                }

                return ret;
            }
            else if (sv_isa(perl_result, "XML::LibXML::Boolean")) {
                return (xmlXPathObjectPtr)
                    xmlXPathNewBoolean(SvIV(SvRV(perl_result)));
            }
            else if (sv_isa(perl_result, "XML::LibXML::Literal")) {
                return (xmlXPathObjectPtr)
                    xmlXPathNewCString(SvPV_nolen(SvRV(perl_result)));
            }
            else if (sv_isa(perl_result, "XML::LibXML::Number")) {
                return (xmlXPathObjectPtr)
                    xmlXPathNewFloat(SvNV(SvRV(perl_result)));
            }
        } else if (SvNOK(perl_result) || SvIOK(perl_result)) {
            return (xmlXPathObjectPtr)xmlXPathNewFloat(SvNV(perl_result));
        } else {
            return (xmlXPathObjectPtr)
                xmlXPathNewCString(SvPV_nolen(perl_result));
    }
    return NULL;
}


/* save XPath context and XPathContextDATA for recursion */
static xmlXPathContextPtr
LibXML_save_context(xmlXPathContextPtr ctxt)
{
    xmlXPathContextPtr copy;
    copy = xmlMalloc(sizeof(xmlXPathContext));
    if (copy) {
	/* backup ctxt */
	memcpy(copy, ctxt, sizeof(xmlXPathContext));
	/* clear namespaces so that they are not freed and overwritten
	   by configure_namespaces */
	ctxt->namespaces = NULL;
	/* backup data */
	copy->user = xmlMalloc(sizeof(XPathContextData));
	if (XPathContextDATA(copy)) {
	    memcpy(XPathContextDATA(copy), XPathContextDATA(ctxt),sizeof(XPathContextData));
	    /* clear ctxt->pool, so that it is not used freed during re-entrance */
	    XPathContextDATA(ctxt)->pool = NULL;
	}
    }
    return copy;
}

/* restore XPath context and XPathContextDATA from a saved copy */
static void
LibXML_restore_context(xmlXPathContextPtr ctxt, xmlXPathContextPtr copy)
{
    dTHX;
    /* cleanup */
    if (XPathContextDATA(ctxt)) {
	/* cleanup newly created pool */
	if (XPathContextDATA(ctxt)->pool != NULL &&
	    SvOK(XPathContextDATA(ctxt)->pool)) {
	    SvREFCNT_dec((SV *)XPathContextDATA(ctxt)->pool);
	}
    }
    if (ctxt->namespaces) {
	/* free namespaces allocated during recursion */
        xmlFree( ctxt->namespaces );
    }

    /* restore context */
    if (copy) {
	/* 1st restore our data */
	if (XPathContextDATA(copy)) {
	    memcpy(XPathContextDATA(ctxt),XPathContextDATA(copy),sizeof(XPathContextData));
	    xmlFree(XPathContextDATA(copy));
	    copy->user = XPathContextDATA(ctxt);
	}
	/* now copy the rest */
	memcpy(ctxt, copy, sizeof(xmlXPathContext));
	xmlFree(copy);
    }
}


/* ****************************************************************
 * Variable Lookup
 * **************************************************************** */
/* Much of the code is borrowed from Matt Sergeant's XML::LibXSLT   */
static xmlXPathObjectPtr
LibXML_generic_variable_lookup(void* varLookupData,
                               const xmlChar *name,
                               const xmlChar *ns_uri)
{
    xmlXPathObjectPtr ret;
    xmlXPathContextPtr ctxt;
    xmlXPathContextPtr copy;
    XPathContextDataPtr data;
    I32 count;
    dTHX;
    dSP;

    ctxt = (xmlXPathContextPtr) varLookupData;
    if ( ctxt == NULL )
	croak("XPathContext: missing xpath context");
    data = XPathContextDATA(ctxt);
    if ( data == NULL )
	croak("XPathContext: missing xpath context private data");
    if ( data->varLookup == NULL || !SvROK(data->varLookup) ||
	 SvTYPE(SvRV(data->varLookup)) != SVt_PVCV )
        croak("XPathContext: lost variable lookup function!");

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    XPUSHs( (data->varData != NULL) ? data->varData : &PL_sv_undef );
    XPUSHs(sv_2mortal(C2Sv(name,NULL)));
    XPUSHs(sv_2mortal(C2Sv(ns_uri,NULL)));

    /* save context to allow recursive usage of XPathContext */
    copy = LibXML_save_context(ctxt);

    PUTBACK ;
    count = call_sv(data->varLookup, G_SCALAR|G_EVAL);
    SPAGAIN;

    /* restore the xpath context */
    LibXML_restore_context(ctxt, copy);

    if (SvTRUE(ERRSV)) {
        (void) POPs;
        croak_obj;
    }
    if (count != 1) croak("XPathContext: variable lookup function returned none or more than one argument!");

    ret = LibXML_perldata_to_LibXMLdata(NULL, POPs);

    PUTBACK;
    FREETMPS;
    LEAVE;
    return ret;
}

/* ****************************************************************
 * Generic Extension Function
 * **************************************************************** */
/* Much of the code is borrowed from Matt Sergeant's XML::LibXSLT   */
static void
LibXML_generic_extension_function(xmlXPathParserContextPtr ctxt, int nargs)
{
    xmlXPathObjectPtr obj,ret;
    xmlNodeSetPtr nodelist = NULL;
    int count;
    SV * perl_dispatch;
    int i;
    STRLEN len;
    ProxyNodePtr owner = NULL;
    SV *key;
    char *strkey;
    const char *function, *uri;
    SV **perl_function;
    dTHX;
    dSP;
    SV * data;
    xmlXPathContextPtr copy;

    /* warn("entered LibXML_generic_extension_function for %s\n",ctxt->context->function); */
    data = (SV *) ctxt->context->funcLookupData;
    if (ctxt->context->funcLookupData == NULL || !SvROK(data) ||
        SvTYPE(SvRV(data)) != SVt_PVHV) {
        croak("XPathContext: lost function lookup data structure!");
    }

    function = (char*) ctxt->context->function;
    uri = (char*) ctxt->context->functionURI;

    key = newSVpvn("",0);
    if (uri && *uri) {
        sv_catpv(key, "{");
        sv_catpv(key, (const char*)uri);
        sv_catpv(key, "}");
    }
    sv_catpv(key, (const char*)function);
    strkey = SvPV(key, len);
    perl_function =
        hv_fetch((HV*)SvRV(data), strkey, len, 0);
    if ( perl_function == NULL || !SvOK(*perl_function) ||
         !(SvPOK(*perl_function) ||
           (SvROK(*perl_function) &&
            SvTYPE(SvRV(*perl_function)) == SVt_PVCV))) {
        croak("XPathContext: lost perl extension function!");
    }
    SvREFCNT_dec(key);

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    XPUSHs(*perl_function);

    /* set up call to perl dispatcher function */
    for (i = 0; i < nargs; i++) {
        obj = (xmlXPathObjectPtr)valuePop(ctxt);
        switch (obj->type) {
        case XPATH_XSLT_TREE:
        case XPATH_NODESET:
            nodelist = obj->nodesetval;
            if ( nodelist ) {
                XPUSHs(sv_2mortal(newSVpv("XML::LibXML::NodeList", 0)));
                XPUSHs(sv_2mortal(newSViv(nodelist->nodeNr)));
                if ( nodelist->nodeNr > 0 ) {
                    int j;
                    const char * cls = "XML::LibXML::Node";
                    xmlNodePtr tnode;
                    SV * element;
                    int l = nodelist->nodeNr;

                    for( j = 0 ; j < l; j++){
                        tnode = nodelist->nodeTab[j];
                        if( tnode != NULL && tnode->doc != NULL) {
                            owner = PmmOWNERPO(PmmNewNode(INT2PTR(xmlNodePtr,tnode->doc)));
                        } else {
                            owner = NULL;
                        }
                        if (tnode->type == XML_NAMESPACE_DECL) {
                            element = NEWSV(0,0);
                            cls = PmmNodeTypeName( tnode );
                            element = sv_setref_pv( element,
                                                    (const char *)cls,
                                                    (void *)xmlCopyNamespace((xmlNsPtr)tnode)
                                );
                        }
                        else {
                            element = PmmNodeToSv(tnode, owner);
                        }
                        XPUSHs( sv_2mortal(element) );
                    }
                }
            } else {
                /* PP: We can't simply leave out an empty nodelist as Matt does! */
                /* PP: The number of arguments must match! */
                XPUSHs(sv_2mortal(newSVpv("XML::LibXML::NodeList", 0)));
                XPUSHs(sv_2mortal(newSViv(0)));
            }
            /* prevent libxml2 from freeing the actual nodes */
            if (obj->boolval) obj->boolval=0;
            break;
        case XPATH_BOOLEAN:
            XPUSHs(sv_2mortal(newSVpv("XML::LibXML::Boolean", 0)));
            XPUSHs(sv_2mortal(newSViv(obj->boolval)));
            break;
        case XPATH_NUMBER:
            XPUSHs(sv_2mortal(newSVpv("XML::LibXML::Number", 0)));
            XPUSHs(sv_2mortal(newSVnv(obj->floatval)));
            break;
        case XPATH_STRING:
            XPUSHs(sv_2mortal(newSVpv("XML::LibXML::Literal", 0)));
            XPUSHs(sv_2mortal(C2Sv(obj->stringval, 0)));
            break;
        default:
            warn("Unknown XPath return type (%d) in call to {%s}%s - assuming string", obj->type, uri, function);
            XPUSHs(sv_2mortal(newSVpv("XML::LibXML::Literal", 0)));
            XPUSHs(sv_2mortal(C2Sv(xmlXPathCastToString(obj), 0)));
        }
        xmlXPathFreeObject(obj);
    }

    /* save context to allow recursive usage of XPathContext */
    copy = LibXML_save_context(ctxt->context);

    /* call perl dispatcher */
    PUTBACK;
    perl_dispatch = sv_2mortal(newSVpv("XML::LibXML::XPathContext::_perl_dispatcher",0));
    count = call_sv(perl_dispatch, G_SCALAR|G_EVAL);
    SPAGAIN;

    /* restore the xpath context */
    LibXML_restore_context(ctxt->context, copy);

    if (SvTRUE(ERRSV)) {
        (void) POPs;
        croak_obj;
    }

    if (count != 1) croak("XPathContext: perl-dispatcher in pm file returned none or more than one argument!");

    ret = LibXML_perldata_to_LibXMLdata(ctxt, POPs);

    valuePush(ctxt, ret);
    PUTBACK;
    FREETMPS;
    LEAVE;
}

static void
LibXML_configure_namespaces( xmlXPathContextPtr ctxt ) {
    xmlNodePtr node = ctxt->node;

    if (ctxt->namespaces != NULL) {
        xmlFree( ctxt->namespaces );
        ctxt->namespaces = NULL;
    }
    if (node != NULL) {
        if (node->type == XML_DOCUMENT_NODE) {
            ctxt->namespaces = xmlGetNsList( node->doc,
                                             xmlDocGetRootElement( node->doc ) );
        } else {
            ctxt->namespaces = xmlGetNsList(node->doc, node);
        }
        ctxt->nsNr = 0;
        if (ctxt->namespaces != NULL) {
	  int cur=0;
	  xmlNsPtr ns;
	  /* we now walk through the list and
	     drop every ns that was declared via registration */
	  while (ctxt->namespaces[cur] != NULL) {
	    ns = ctxt->namespaces[cur];
	    if (ns->prefix==NULL ||
		xmlHashLookup(ctxt->nsHash, ns->prefix) != NULL) {
	      /* drop it */
	      ctxt->namespaces[cur]=NULL;
	    } else {
	      if (cur != ctxt->nsNr) {
		/* move the item to the new tail */
		ctxt->namespaces[ctxt->nsNr]=ns;
		ctxt->namespaces[cur]=NULL;
	      }
	      ctxt->nsNr++;
	    }
	    cur++;
	  }
        }
    }
}

static void
LibXML_configure_xpathcontext( xmlXPathContextPtr ctxt ) {
    xmlNodePtr node = PmmSvNode(XPathContextDATA(ctxt)->node);

    if (node != NULL) {
        ctxt->doc = node->doc;
    } else {
        ctxt->doc = NULL;
    }
    ctxt->node = node;
    LibXML_configure_namespaces(ctxt);
}

#ifdef HAVE_READER_SUPPORT

static void
LibXML_set_reader_preserve_flag( xmlTextReaderPtr reader ) {
    HV *hash;
    char key[32];

    hash = get_hv("XML::LibXML::Reader::_preserve_flag", 0);
    if (!hash) {
        return;
    }

    (void) snprintf(key, sizeof(key), "%p", reader);
    (void) hv_store(hash, key, strlen(key), newSV(0), 0);
}

static int
LibXML_get_reader_preserve_flag( xmlTextReaderPtr reader ) {
    HV *hash;
    char key[32];

    hash = get_hv("XML::LibXML::Reader::_preserve_flag", 0);
    if (!hash) {
        return 0;
    }

    (void) snprintf(key, sizeof(key), "%p", reader);
    if ( hv_exists(hash, key, strlen(key)) ) {
        (void) hv_delete(hash, key, strlen(key), G_DISCARD);
        return 1;
    }

    return 0;
}

#endif /* HAVE_READER_SUPPORT */

extern void boot_XML__LibXML__Devel(pTHX_ CV*);

MODULE = XML::LibXML         PACKAGE = XML::LibXML

PROTOTYPES: DISABLE

BOOT:
    /* Load Devel first, so debug_memory can
       be called before any allocation. */

    /* The ++ is a bit hacky, but boot_blahblah_Devel, being an
     * XSUB body, will try to pop once more the mark we have just
     * (implicitly) popped, this boot sector also being an XSUB body */
    PL_markstack_ptr++;
    boot_XML__LibXML__Devel(aTHX_ cv);
    LIBXML_TEST_VERSION
    xmlInitParser();
    PmmSAXInitialize(aTHX);
#ifndef WITH_SERRORS
    xmlGetWarningsDefaultValue = 0;
#endif
#ifdef LIBXML_CATALOG_ENABLED
    /* xmlCatalogSetDebug(10); */
    xmlInitializeCatalog(); /* use catalog data */
#endif


void
_CLONE( class )
    CODE:
#ifdef XML_LIBXML_THREADS
     if( PmmUSEREGISTRY )
       PmmCloneProxyNodes();
#endif

int
_leaked_nodes()
    CODE:
     RETVAL = 0;
#ifdef XML_LIBXML_THREADS
     if( PmmUSEREGISTRY )
       RETVAL = PmmProxyNodeRegistrySize();
#endif
    OUTPUT:
        RETVAL

void
_dump_registry()
	PPCODE:
#ifdef XML_LIBXML_THREADS
		if( PmmUSEREGISTRY )
			PmmDumpRegistry(PmmREGISTRY);
#endif

const char *
LIBXML_DOTTED_VERSION()
    CODE:
        RETVAL = LIBXML_DOTTED_VERSION;
    OUTPUT:
        RETVAL


int
LIBXML_VERSION()
    CODE:
        RETVAL = LIBXML_VERSION;
    OUTPUT:
        RETVAL

int
HAVE_STRUCT_ERRORS()
    CODE:
#ifdef WITH_SERRORS
        RETVAL = 1;
#else
        RETVAL = 0;
#endif
    OUTPUT:
        RETVAL

int
HAVE_SCHEMAS()
    CODE:
#ifdef HAVE_SCHEMAS
        RETVAL = 1;
# if LIBXML_VERSION == 20904
        /* exists but broken https://github.com/shlomif/libxml2-2.9.4-reader-schema-regression */
        RETVAL = 0;
# endif
#else
        RETVAL = 0;
#endif
    OUTPUT:
        RETVAL

int
HAVE_READER()
    CODE:
#ifdef HAVE_READER_SUPPORT
        RETVAL = 1;
#else
        RETVAL = 0;
#endif
    OUTPUT:
        RETVAL

int
HAVE_THREAD_SUPPORT()
    CODE:
#ifdef XML_LIBXML_THREADS
        RETVAL = (PmmUSEREGISTRY ? 1 : 0);
#else
        RETVAL = 0;
#endif
    OUTPUT:
        RETVAL


const char *
LIBXML_RUNTIME_VERSION()
    CODE:
        RETVAL = xmlParserVersion;
    OUTPUT:
        RETVAL

void
END()
    CODE:
        xmlCleanupParser();

int
INIT_THREAD_SUPPORT()
    CODE:
#ifdef XML_LIBXML_THREADS
      SV *threads = get_sv("threads::threads", 0); /* no create */
      if( threads && SvOK(threads) && SvTRUE(threads) ) {
        PROXY_NODE_REGISTRY_MUTEX = get_sv("XML::LibXML::__PROXY_NODE_REGISTRY_MUTEX",0);
	RETVAL = 1;
      } else {
	croak("XML::LibXML ':threads_shared' can only be used after 'use threads'");
      }
#else
        RETVAL = 0;
#endif
    OUTPUT:
        RETVAL

void
DISABLE_THREAD_SUPPORT()
    CODE:
#ifdef XML_LIBXML_THREADS
        PROXY_NODE_REGISTRY_MUTEX = NULL;
#else
        croak("XML::LibXML compiled without threads!");
#endif

SV*
_parse_string(self, string, dir = &PL_sv_undef)
        SV * self
        SV * string
        SV * dir
    PREINIT:
        char * directory = NULL;
        STRLEN len;
        const char * ptr;
        HV * real_obj;
        int well_formed;
        int valid;
        int validate;
        xmlDocPtr real_doc;
        int recover = 0;
	PREINIT_SAVED_ERROR
    INIT:
        if (SvPOK(dir)) {
            directory = SvPV(dir, len);
            if (len <= 0) {
                directory = NULL;
            }
        }
        /* If string is a reference to a string - dereference it.
         * See: https://rt.cpan.org/Ticket/Display.html?id=64051 (broke it)
         *      https://rt.cpan.org/Ticket/Display.html?id=77864 (fixed it) */
        if (SvROK(string) && !SvOBJECT(SvRV(string))) {
            string = SvRV(string);
        }
        ptr = SvPV_const(string, len);
        if (len <= 0) {
            croak("Empty string\n");
            XSRETURN_UNDEF;
        }
    CODE:
        RETVAL = &PL_sv_undef;
        INIT_ERROR_HANDLER;
        {
            xmlParserCtxtPtr ctxt = xmlCreateMemoryParserCtxt(ptr, len);
            if (ctxt == NULL) {
	        CLEANUP_ERROR_HANDLER;
                REPORT_ERROR(1);
                croak("Could not create memory parser context!\n");
            }
            xs_warn( "context created\n");
            real_obj = LibXML_init_parser(self, ctxt);
            recover = LibXML_get_recover(real_obj);


            if ( directory != NULL ) {
                ctxt->directory = directory;
            }
            ctxt->_private = (void*)self;

            /* make libxml2-2.6 display line number on error */
            if ( ctxt->input != NULL ) {
                if (directory != NULL) {
		  ctxt->input->filename = (char *) xmlStrdup((const xmlChar *) directory);
                } else {
		  ctxt->input->filename = (char *) xmlStrdup((const xmlChar *) "");
                }
            }

            xs_warn( "context initialized\n" );

            xmlParseDocument(ctxt);
            xs_warn( "document parsed \n");

            ctxt->directory = NULL;
            well_formed = ctxt->wellFormed;
            valid = ctxt->valid;
            validate = ctxt->validate;
            real_doc = ctxt->myDoc;
            ctxt->myDoc = NULL;
            xmlFreeParserCtxt(ctxt);
        }
        if ( real_doc != NULL ) {
  	    if (real_doc->URL != NULL) { /* free "" assigned above */
               xmlFree((char*) real_doc->URL);
               real_doc->URL = NULL;
            }

            if ( directory == NULL ) {
                SV * newURI = sv_2mortal(newSVpvf("unknown-%p", (void*)real_doc));
                real_doc->URL = xmlStrdup((const xmlChar*)SvPV_nolen(newURI));
            } else {
                real_doc->URL = xmlStrdup((const xmlChar*)directory);
            }
            if ( ! LibXML_will_die_ctx(saved_error, recover) &&
		 (recover || ( well_formed &&
                              ( !validate
                                || ( valid || ( real_doc->intSubset == NULL
                                                && real_doc->extSubset == NULL )))))) {
                RETVAL = LibXML_NodeToSv( real_obj, INT2PTR(xmlNodePtr,real_doc) );
            } else {
                xmlFreeDoc(real_doc);
		real_doc=NULL;
            }
        }

        LibXML_cleanup_parser();
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(recover);
    OUTPUT:
        RETVAL

int
_parse_sax_string(self, string)
        SV * self
        SV * string
    PREINIT:
        STRLEN len;
        char * ptr;
        HV * real_obj;
        int recover = 0;
        PREINIT_SAVED_ERROR
    INIT:
        ptr = SvPV(string, len);
        if (len <= 0) {
            croak("Empty string\n");
            XSRETURN_UNDEF;
        }
    CODE:
        RETVAL = 0;
        INIT_ERROR_HANDLER;

        {
            xmlParserCtxtPtr ctxt = xmlCreateMemoryParserCtxt((const char*)ptr, len);
            if (ctxt == NULL) {
                CLEANUP_ERROR_HANDLER;
                REPORT_ERROR(recover ? recover : 1);
                croak("Could not create memory parser context!\n");
            }
            xs_warn( "context created\n");
            real_obj = LibXML_init_parser(self, ctxt);
            recover = LibXML_get_recover(real_obj);

            PmmSAXInitContext( ctxt, self, saved_error );
            xs_warn( "context initialized \n");
            {
                RETVAL = xmlParseDocument(ctxt);
                xs_warn( "document parsed \n");
            }

            PmmSAXCloseContext(ctxt);
            xmlFreeParserCtxt(ctxt);
        }

        LibXML_cleanup_parser();
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(recover);
    OUTPUT:
        RETVAL

SV*
_parse_fh(self, fh, dir = &PL_sv_undef)
        SV * self
        SV * fh
        SV * dir
    PREINIT:
        STRLEN len;
        char * directory = NULL;
        HV * real_obj;
        int well_formed;
        int valid;
        int validate;
        xmlDocPtr real_doc;
        int recover = 0;
        PREINIT_SAVED_ERROR
    INIT:
        if (SvPOK(dir)) {
            directory = SvPV(dir, len);
            if (len <= 0) {
                directory = NULL;
            }
        }
    CODE:
        RETVAL = &PL_sv_undef;
        INIT_ERROR_HANDLER;

        {
            int read_length;
            char buffer[1024];
            xmlParserCtxtPtr ctxt;

            read_length = LibXML_read_perl(fh, buffer, 4);
            if (read_length <= 0) {
                CLEANUP_ERROR_HANDLER;
                croak( "Empty Stream\n" );
            }

            ctxt = xmlCreatePushParserCtxt(NULL, NULL, buffer, read_length, NULL);
            if (ctxt == NULL) {
                CLEANUP_ERROR_HANDLER;
                REPORT_ERROR(1);
                croak("Could not create xml push parser context!\n");
            }
            xs_warn( "context created\n");
            real_obj = LibXML_init_parser(self, ctxt);
            recover = LibXML_get_recover(real_obj);
#if LIBXML_VERSION > 20600
	    /* dictionaries not support yet */
	    ctxt->dictNames = 0;
#endif
            if ( directory != NULL ) {
                ctxt->directory = directory;
            }
            ctxt->_private = (void*)self;
            xs_warn( "context initialized \n");
            {
                int ret;
                while ((read_length = LibXML_read_perl(fh, buffer, 1024))) {
                    ret = xmlParseChunk(ctxt, buffer, read_length, 0);
                    if ( ret != 0 ) {
                        break;
                    }
                }
                ret = xmlParseChunk(ctxt, buffer, 0, 1);
                xs_warn( "document parsed \n");
            }

            ctxt->directory = NULL;
            well_formed = ctxt->wellFormed;
            valid = ctxt->valid;
            validate = ctxt->validate;
            real_doc = ctxt->myDoc;
            ctxt->myDoc = NULL;
            xmlFreeParserCtxt(ctxt);
        }

        if ( real_doc != NULL ) {

            if ( directory == NULL ) {
                SV * newURI = sv_2mortal(newSVpvf("unknown-%p", (void*)real_doc));
                real_doc->URL = xmlStrdup((const xmlChar*)SvPV_nolen(newURI));
            } else {
                real_doc->URL = xmlStrdup((const xmlChar*)directory);
            }

            if ( ! LibXML_will_die_ctx(saved_error, recover) &&
		 (recover || ( well_formed &&
                              ( !validate
                                || ( valid || ( real_doc->intSubset == NULL
                                                && real_doc->extSubset == NULL )))))) {
                RETVAL = LibXML_NodeToSv( real_obj, INT2PTR(xmlNodePtr,real_doc) );
            } else {
                xmlFreeDoc(real_doc);
		real_doc=NULL;
            }
        }

        LibXML_cleanup_parser();
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(recover);
    OUTPUT:
        RETVAL

void
_parse_sax_fh(self, fh, dir = &PL_sv_undef)
        SV * self
        SV * fh
        SV * dir
    PREINIT:
        STRLEN len;
        char * directory = NULL;
        HV * real_obj;
        int recover = 0;
        PREINIT_SAVED_ERROR
    INIT:
        if (SvPOK(dir)) {
            directory = SvPV(dir, len);
            if (len <= 0) {
                directory = NULL;
            }
        }
    CODE:
        INIT_ERROR_HANDLER;
        {
            int read_length;
            char buffer[1024];
            xmlSAXHandlerPtr sax;
            xmlParserCtxtPtr ctxt;

            read_length = LibXML_read_perl(fh, buffer, 4);
            if (read_length <= 0) {
                CLEANUP_ERROR_HANDLER;
                croak( "Empty Stream\n" );
            }

            sax = PSaxGetHandler();
            ctxt = xmlCreatePushParserCtxt(sax, NULL, buffer, read_length, NULL);
            if (ctxt == NULL) {
                CLEANUP_ERROR_HANDLER;
                REPORT_ERROR(recover ? recover : 1);
                croak("Could not create xml push parser context!\n");
            }
            xs_warn( "context created\n");
            real_obj = LibXML_init_parser(self, ctxt);
            recover = LibXML_get_recover(real_obj);

            if ( directory != NULL ) {
                ctxt->directory = directory;
            }
            PmmSAXInitContext( ctxt, self, saved_error );
            xs_warn( "context initialized \n");

            {
                int ret;
                while ((read_length = LibXML_read_perl(fh, buffer, 1024))) {
                    ret = xmlParseChunk(ctxt, buffer, read_length, 0);
                    if ( ret != 0 ) {
                        break;
                    }
                }
                ret = xmlParseChunk(ctxt, buffer, 0, 1);
                xs_warn( "document parsed \n");
            }

            ctxt->directory = NULL;
            xmlFree(ctxt->sax);
            ctxt->sax = NULL;
            xmlFree(sax);
            PmmSAXCloseContext(ctxt);
            xmlFreeParserCtxt(ctxt);
        }
        CLEANUP_ERROR_HANDLER;
        LibXML_cleanup_parser();
        REPORT_ERROR(recover);

SV*
_parse_file(self, filename_sv)
        SV * self
        SV * filename_sv
    PREINIT:
        STRLEN len;
        char * filename;
        HV * real_obj;
        int well_formed;
        int valid;
        int validate;
        xmlDocPtr real_doc;
        int recover = 0;
        PREINIT_SAVED_ERROR
    INIT:
        filename = SvPV(filename_sv, len);
        if (len <= 0) {
            croak("Empty filename\n");
            XSRETURN_UNDEF;
        }
    CODE:
        RETVAL = &PL_sv_undef;
        INIT_ERROR_HANDLER;

        {
            xmlParserCtxtPtr ctxt = xmlCreateFileParserCtxt(filename);
            if (ctxt == NULL) {
                CLEANUP_ERROR_HANDLER;
                REPORT_ERROR(1);
                croak("Could not create file parser context for file \"%s\": %s\n",
                      filename, strerror(errno));
            }
            xs_warn( "context created\n");
            real_obj = LibXML_init_parser(self, ctxt);
            recover = LibXML_get_recover(real_obj);

            ctxt->_private = (void*)self;

            xs_warn( "context initialized\n" );
            xmlParseDocument(ctxt);
            xs_warn( "document parsed \n");

            well_formed = ctxt->wellFormed;
            valid = ctxt->valid;
            validate = ctxt->validate;
            real_doc = ctxt->myDoc;
            ctxt->myDoc = NULL;
            xmlFreeParserCtxt(ctxt);
        }

        if ( real_doc != NULL ) {
            if ( ! LibXML_will_die_ctx(saved_error, recover) &&
		 (recover || ( well_formed &&
                              ( !validate
                                || ( valid || ( real_doc->intSubset == NULL
                                                && real_doc->extSubset == NULL )))))) {
                RETVAL = LibXML_NodeToSv( real_obj, INT2PTR(xmlNodePtr,real_doc) );
            } else {
                xmlFreeDoc(real_doc);
		real_doc=NULL;
            }
        }

        LibXML_cleanup_parser();
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(recover);
    OUTPUT:
        RETVAL

void
_parse_sax_file(self, filename_sv)
        SV * self
        SV * filename_sv
    PREINIT:
        STRLEN len;
        char * filename;
        HV * real_obj;
        int recover = 0;
        PREINIT_SAVED_ERROR
    INIT:
        filename = SvPV(filename_sv, len);
        if (len <= 0) {
            croak("Empty filename\n");
            XSRETURN_UNDEF;
        }
    CODE:
        INIT_ERROR_HANDLER;

        {
            xmlParserCtxtPtr ctxt = xmlCreateFileParserCtxt(filename);
            if (ctxt == NULL) {
                CLEANUP_ERROR_HANDLER;
                REPORT_ERROR(recover ? recover : 1);
                croak("Could not create file parser context for file \"%s\": %s\n",
                      filename, strerror(errno));
            }
            xs_warn( "context created\n");
            real_obj = LibXML_init_parser(self, ctxt);
            recover = LibXML_get_recover(real_obj);

            ctxt->sax = PSaxGetHandler();
            PmmSAXInitContext( ctxt, self, saved_error );
            xs_warn( "context initialized \n");

            {
                xmlParseDocument(ctxt);
                xs_warn( "document parsed \n");
            }

            PmmSAXCloseContext(ctxt);
            xmlFreeParserCtxt(ctxt);
        }

        LibXML_cleanup_parser();
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(recover);

SV*
_parse_html_string(self, string, svURL, svEncoding, options = 0)
        SV * self
        SV * string
	SV * svURL
	SV * svEncoding
        int options
    PREINIT:
        STRLEN len;
        char * ptr;
        char* URL = NULL;
        const char * encoding = NULL;
        HV * real_obj;
        htmlDocPtr real_doc;
        int recover = 0;
        PREINIT_SAVED_ERROR
    INIT:
        /* If string is a reference to a string - dereference it.
         * See: https://rt.cpan.org/Ticket/Display.html?id=64051 (broke it)
         *      https://rt.cpan.org/Ticket/Display.html?id=77864 (fixed it) */
        if (SvROK(string) && !SvOBJECT(SvRV(string))) {
            string = SvRV(string);
        }
        ptr = SvPV(string, len);
        if (len <= 0) {
            croak("Empty string\n");
            XSRETURN_UNDEF;
        }
        if (SvOK(svURL))
          URL = SvPV_nolen( svURL );
        if (SvOK(svEncoding))
          encoding = SvPV_nolen( svEncoding );
    CODE:
        RETVAL = &PL_sv_undef;
        INIT_ERROR_HANDLER;
        real_obj = LibXML_init_parser(self,NULL);
        if (encoding == NULL && SvUTF8( string )) {
	  encoding = "UTF-8";
        }
        if (options & HTML_PARSE_RECOVER) {
          recover = ((options & HTML_PARSE_NOERROR) ? 2 : 1);
        }
#if LIBXML_VERSION >= 20627
        real_doc = htmlReadDoc((xmlChar*)ptr, URL, encoding, options);
#else
        real_doc = htmlParseDoc((xmlChar*)ptr, encoding);
        if ( real_doc ) {
            if (real_doc->URL) xmlFree((xmlChar *)real_doc->URL);
   	    if (URL) {
                real_doc->URL = xmlStrdup((const xmlChar*) URL);
            }
        }
#endif
        if ( real_doc ) {
	   if (URL==NULL) {
             SV * newURI = sv_2mortal(newSVpvf("unknown-%p", (void*)real_doc));
             real_doc->URL = xmlStrdup((const xmlChar*)SvPV_nolen(newURI));
           }
            /* This HTML memory parser doesn't use a ctxt; there is no "well-formed"
             * distinction, and if it manages to parse the HTML, it returns non-null. */
           RETVAL = LibXML_NodeToSv( real_obj, INT2PTR(xmlNodePtr,real_doc) );
        }

        LibXML_cleanup_parser();
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(recover);
    OUTPUT:
        RETVAL


SV*
_parse_html_file(self, filename_sv, svURL, svEncoding, options = 0)
        SV * self
        SV * filename_sv
	SV * svURL
	SV * svEncoding
	int options
    PREINIT:
        STRLEN len;
        char * filename;
        char * URL = NULL;
	char * encoding = NULL;
        HV * real_obj;
        htmlDocPtr real_doc;
        int recover = 0;
        PREINIT_SAVED_ERROR
    INIT:
        filename = SvPV(filename_sv, len);
        if (len <= 0) {
            croak("Empty filename\n");
            XSRETURN_UNDEF;
        }
        if (SvOK(svURL))
          URL = SvPV_nolen( svURL );
        if (SvOK(svEncoding))
          encoding = SvPV_nolen( svEncoding );
    CODE:
        RETVAL = &PL_sv_undef;
        INIT_ERROR_HANDLER;
        real_obj = LibXML_init_parser(self,NULL);
        if (options & HTML_PARSE_RECOVER) {
          recover = ((options & HTML_PARSE_NOERROR) ? 2 : 1);
        }
#if LIBXML_VERSION >= 20627
        real_doc = htmlReadFile((const char *)filename,
				encoding,
				options);
#else
        real_doc = htmlParseFile((const char *)filename, encoding);
#endif
        if ( real_doc != NULL ) {

            /* This HTML file parser doesn't use a ctxt; there is no "well-formed"
             * distinction, and if it manages to parse the HTML, it returns non-null. */
	    if (URL) {
                if (real_doc->URL) xmlFree((xmlChar*) real_doc->URL);
                real_doc->URL = xmlStrdup((const xmlChar*) URL);
	    }
            RETVAL = LibXML_NodeToSv( real_obj, INT2PTR(xmlNodePtr,real_doc) );

        }
        CLEANUP_ERROR_HANDLER;
        LibXML_cleanup_parser();
        REPORT_ERROR(recover);
    OUTPUT:
        RETVAL

SV*
_parse_html_fh(self, fh, svURL, svEncoding, options = 0)
        SV * self
        SV * fh
	SV * svURL
	SV * svEncoding
        int options
    PREINIT:
        HV * real_obj;
        htmlDocPtr real_doc;
        int recover = 0;
        char * URL = NULL;
        PREINIT_SAVED_ERROR
#if LIBXML_VERSION >= 20627
        char * encoding = NULL;
#else
        xmlCharEncoding enc = XML_CHAR_ENCODING_NONE;
#endif
    INIT:
        if (SvOK(svURL))
          URL = SvPV_nolen( svURL );
#if LIBXML_VERSION >= 20627
        if (SvOK(svEncoding))
          encoding = SvPV_nolen( svEncoding );
#else
        if (SvOK(svEncoding))
          enc = xmlParseCharEncoding(SvPV_nolen( svEncoding ));
#endif
    CODE:
        RETVAL = &PL_sv_undef;
        INIT_ERROR_HANDLER;
        real_obj = LibXML_init_parser(self,NULL);
        if (options & HTML_PARSE_RECOVER) {
          recover = ((options & HTML_PARSE_NOERROR) ? 2 : 1);
        }
#if LIBXML_VERSION >= 20627

        real_doc = htmlReadIO((xmlInputReadCallback) LibXML_read_perl,
                              NULL,
			      (void *) fh,
			      URL,
			      encoding,
			      options);
#else /* LIBXML_VERSION >= 20627 */
        {
            int read_length;
            int well_formed;
            char buffer[1024];
            htmlParserCtxtPtr ctxt;

            read_length = LibXML_read_perl(fh, buffer, 4);
            if (read_length <= 0) {
                CLEANUP_ERROR_HANDLER;
                croak( "Empty Stream\n" );
            }
            ctxt = htmlCreatePushParserCtxt(NULL, NULL, buffer, read_length,
                                            URL, enc);
            if (ctxt == NULL) {
                CLEANUP_ERROR_HANDLER;
                REPORT_ERROR(recover ? recover : 1);
                croak("Could not create html push parser context!\n");
            }
            ctxt->_private = (void*)self;
            {
                int ret;
                while ((read_length = LibXML_read_perl(fh, buffer, 1024))) {
                    ret = htmlParseChunk(ctxt, buffer, read_length, 0);
                    if ( ret != 0 ) {
                        break;
                    }
                }
                ret = htmlParseChunk(ctxt, buffer, 0, 1);
            }
            well_formed = ctxt->wellFormed;
            real_doc = ctxt->myDoc;
            ctxt->myDoc = NULL;
            htmlFreeParserCtxt(ctxt);
        }
#endif /* LIBXML_VERSION >= 20627 */
        if ( real_doc != NULL ) {
            if (real_doc->URL) xmlFree((xmlChar*) real_doc->URL);
	    if (URL) {
                real_doc->URL = xmlStrdup((const xmlChar*) URL);
	    } else {
                SV * newURI = sv_2mortal(newSVpvf("unknown-%p", (void*)real_doc));
                real_doc->URL = xmlStrdup((const xmlChar*)SvPV_nolen(newURI));
            }

	    RETVAL = LibXML_NodeToSv( real_obj, INT2PTR(xmlNodePtr,real_doc) );
        }

        LibXML_cleanup_parser();
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(recover);
    OUTPUT:
        RETVAL

SV*
_parse_xml_chunk(self, svchunk, enc = &PL_sv_undef)
        SV * self
        SV * svchunk
        SV * enc
    PREINIT:
        STRLEN len;
        const char * encoding = "UTF-8";
        HV * real_obj;
        int recover = 0;
        xmlChar * chunk;
        xmlNodePtr rv = NULL;
        PREINIT_SAVED_ERROR
    INIT:
        if (SvPOK(enc)) {
            encoding = SvPV(enc, len);
            if (len <= 0) {
                encoding = "UTF-8";
            }
        }
    CODE:
        RETVAL = &PL_sv_undef;
        INIT_ERROR_HANDLER;
        real_obj = LibXML_init_parser(self,NULL);

        chunk = Sv2C(svchunk, (const xmlChar*)encoding);

        if ( chunk != NULL ) {
            recover = LibXML_get_recover(real_obj);

            rv = domReadWellBalancedString( NULL, chunk, recover );

            if ( rv != NULL ) {
                xmlNodePtr fragment= NULL;
                xmlNodePtr rv_end = NULL;

                /* now we append the nodelist to a document
                   fragment which is unbound to a Document!!!! */

                /* step 1: create the fragment */
                fragment = xmlNewDocFragment( NULL );
                RETVAL = LibXML_NodeToSv(real_obj, fragment);

                /* step 2: set the node list to the fragment */
                fragment->children = rv;
                rv_end = rv;
                while ( rv_end->next != NULL ) {
                    rv_end->parent = fragment;
                    rv_end = rv_end->next;
                }
                /* the following line is important, otherwise we'll have
                   occasional segmentation faults
                 */
                rv_end->parent = fragment;
                fragment->last = rv_end;
            }

            /* free the chunk we created */
            xmlFree( chunk );
        }

        LibXML_cleanup_parser();
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(recover);

	if (rv == NULL) {
            croak("_parse_xml_chunk: chunk parsing failed\n");
        }
    OUTPUT:
        RETVAL

void
_parse_sax_xml_chunk(self, svchunk, enc = &PL_sv_undef)
        SV * self
        SV * svchunk
        SV * enc
    PREINIT:
        STRLEN len;
        char * ptr;
        const char * encoding = "UTF-8";
        HV * real_obj;
        int recover = 0;
        xmlChar * chunk;
        int retCode              = -1;
        xmlNodePtr nodes         = NULL;
        xmlSAXHandlerPtr handler = NULL;
        PREINIT_SAVED_ERROR
    INIT:
        if (SvPOK(enc)) {
            encoding = SvPV(enc, len);
            if (len <= 0) {
                encoding = "UTF-8";
            }
        }
        ptr = SvPV(svchunk, len);
        if (len <= 0) {
            croak("Empty string\n");
        }
    CODE:
        INIT_ERROR_HANDLER;

        chunk = Sv2C(svchunk, (const xmlChar*)encoding);

        if ( chunk != NULL ) {
            xmlParserCtxtPtr ctxt = xmlCreateMemoryParserCtxt((const char*)ptr, len);
            if (ctxt == NULL) {
                CLEANUP_ERROR_HANDLER;
                REPORT_ERROR(recover ? recover : 1);
                croak("Could not create memory parser context!\n");
            }
            xs_warn( "context created\n");
            real_obj = LibXML_init_parser(self,ctxt);
            recover = LibXML_get_recover(real_obj);

            PmmSAXInitContext( ctxt, self, saved_error );
            handler = PSaxGetHandler();

            retCode = xmlParseBalancedChunkMemory( NULL,
                                                   handler,
                                                   ctxt,
                                                   0,
                                                   chunk,
                                                   &nodes );

            xmlFree( handler );
            PmmSAXCloseContext(ctxt);
            xmlFreeParserCtxt(ctxt);

            /* free the chunk we created */
            xmlFree( chunk );
        }

        LibXML_cleanup_parser();
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(recover);

	if (retCode == -1) {
            croak("_parse_sax_xml_chunk: chunk parsing failed\n");
        }

int
_processXIncludes(self, doc, options=0)
        SV * self
        SV * doc
        int options
    PREINIT:
        xmlDocPtr real_doc;
        HV * real_obj;
        int recover = 0;
        PREINIT_SAVED_ERROR
    INIT:
        real_doc = (xmlDocPtr) PmmSvNode(doc);
        if (real_doc == NULL) {
            croak("No document to process!\n");
            XSRETURN_UNDEF;
        }
    CODE:
        RETVAL = 0;
        INIT_ERROR_HANDLER;
        real_obj = LibXML_init_parser(self,NULL);
        recover = LibXML_get_recover(real_obj);

        RETVAL = xmlXIncludeProcessFlags(real_doc,options);

        LibXML_cleanup_parser();
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(recover);

        if ( RETVAL < 0 ) {
            croak( "unknown error during XInclude processing\n" );
            XSRETURN_UNDEF;
        } else if ( RETVAL == 0 ) {
            RETVAL = 1;
        }
    OUTPUT:
        RETVAL

SV*
_start_push(self, with_sax=0)
        SV * self
        int with_sax
    PREINIT:
        HV * real_obj;
        int recover = 0;
        xmlParserCtxtPtr ctxt = NULL;
        PREINIT_SAVED_ERROR
    CODE:
        RETVAL = &PL_sv_undef;
        INIT_ERROR_HANDLER;

        /* create empty context */
        ctxt = xmlCreatePushParserCtxt( NULL, NULL, NULL, 0, NULL );
        real_obj = LibXML_init_parser(self,ctxt);
        recover = LibXML_get_recover(real_obj);
        if ( with_sax == 1 ) {
	    PmmSAXInitContext( ctxt, self, saved_error );
        }

        RETVAL = PmmContextSv( ctxt );

        LibXML_cleanup_parser();
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(recover);
    OUTPUT:
        RETVAL

int
_push(self, pctxt, data)
        SV * self
        SV * pctxt
        SV * data
    PREINIT:
        HV * real_obj;
        int recover = 0;
        xmlParserCtxtPtr ctxt = NULL;
        STRLEN len = 0;
        char * chunk = NULL;
        PREINIT_SAVED_ERROR
    INIT:
        ctxt = PmmSvContext( pctxt );
        if ( ctxt == NULL ) {
            croak( "parser context already freed\n" );
            XSRETURN_UNDEF;
        }
        if ( data == &PL_sv_undef ) {
            XSRETURN_UNDEF;
        }
        chunk = SvPV( data, len );
        if ( len <= 0 ) {
            xs_warn( "empty string" );
            XSRETURN_UNDEF;
        }
    CODE:
        RETVAL = 0;
        INIT_ERROR_HANDLER;
        real_obj = LibXML_init_parser(self,NULL);
        recover = LibXML_get_recover(real_obj);

        xmlParseChunk(ctxt, (const char *)chunk, len, 0);

        LibXML_cleanup_parser();
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(recover);

        if ( ctxt->wellFormed == 0 ) {
            croak( "XML not well-formed in xmlParseChunk\n" );
            XSRETURN_UNDEF;
        }
        RETVAL = 1;
    OUTPUT:
        RETVAL

SV*
_end_push(self, pctxt, restore)
        SV * self
        SV * pctxt
        int restore
    PREINIT:
        HV * real_obj;
        int well_formed;
        xmlParserCtxtPtr ctxt = NULL;
        xmlDocPtr real_doc = NULL;
        PREINIT_SAVED_ERROR
    INIT:
        ctxt = PmmSvContext( pctxt );
        if ( ctxt == NULL ) {
            croak( "parser context already freed\n" );
            XSRETURN_UNDEF;
        }
    CODE:
        RETVAL = &PL_sv_undef;
        INIT_ERROR_HANDLER;
        real_obj = LibXML_init_parser(self,NULL);

        xmlParseChunk(ctxt, "", 0, 1); /* finish the parse */
        xs_warn( "Finished with push parser\n" );

        well_formed = ctxt->wellFormed;
        real_doc = ctxt->myDoc;
        ctxt->myDoc = NULL;
        xmlFreeParserCtxt(ctxt);
        PmmNODE( SvPROXYNODE( pctxt ) ) = NULL;

        if ( real_doc != NULL ) {
            if ( restore || well_formed ) {
                RETVAL = LibXML_NodeToSv( real_obj, INT2PTR(xmlNodePtr,real_doc) );
            } else {
                xmlFreeDoc(real_doc);
                real_doc = NULL;
            }
        }

        LibXML_cleanup_parser();
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(restore);

        if ( real_doc == NULL ){
            croak( "no document found!\n" );
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

void
_end_sax_push(self, pctxt)
        SV * self
        SV * pctxt
    PREINIT:
        HV * real_obj;
        xmlParserCtxtPtr ctxt = NULL;
        PREINIT_SAVED_ERROR
    INIT:
        ctxt = PmmSvContext( pctxt );
        if ( ctxt == NULL ) {
            croak( "parser context already freed\n" );
        }
    CODE:
        INIT_ERROR_HANDLER;
        real_obj = LibXML_init_parser(self,NULL);

        xmlParseChunk(ctxt, "", 0, 1); /* finish the parse */
        xs_warn( "Finished with SAX push parser\n" );

        xmlFree(ctxt->sax);
        ctxt->sax = NULL;
        PmmSAXCloseContext(ctxt);
        xmlFreeParserCtxt(ctxt);
        PmmNODE( SvPROXYNODE( pctxt ) ) = NULL;

        LibXML_cleanup_parser();
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(0);

SV*
import_GDOME( CLASS, sv_gdome, deep=1 )
        SV * sv_gdome
        int deep
    PREINIT:
        xmlNodePtr node  = NULL;
    INIT:
        RETVAL = &PL_sv_undef;
#ifndef XML_LIBXML_GDOME_SUPPORT
        croak( "GDOME Support not compiled" );
#endif
        if ( sv_gdome == NULL || sv_gdome == &PL_sv_undef ) {
            croak( "no XML::GDOME data found" );
        }
#ifdef XML_LIBXML_GDOME_SUPPORT
        else {
            GdomeNode* gnode = NULL;
            gnode = (GdomeNode*)SvIV((SV*)SvRV( sv_gdome ));
            if ( gnode == NULL ) {
                croak( "no XML::GDOME data found (datastructure empty)" );
            }

            node = gdome_xml_n_get_xmlNode( gnode );
            if ( node == NULL ) {
                croak( "no XML::LibXML node found in GDOME object" );
            }
        }
#endif
    CODE:
        if ( node->type == XML_NAMESPACE_DECL ) {
            const char * CLASS = "XML::LibXML::Namespace";
            RETVAL = NEWSV(0,0);
            RETVAL = sv_setref_pv( RETVAL,
                                   CLASS,
                                   (void*)xmlCopyNamespace((xmlNsPtr)node) );
        }
        else {
            RETVAL = PmmNodeToSv( PmmCloneNode( node, deep ), NULL );
        }
    OUTPUT:
        RETVAL


SV*
export_GDOME( CLASS, sv_libxml, deep=1 )
        SV * sv_libxml
        int deep
    PREINIT:
        xmlNodePtr node  = NULL, retnode = NULL;
    INIT:
        RETVAL = &PL_sv_undef;
#ifndef XML_LIBXML_GDOME_SUPPORT
        croak( "GDOME Support not configured!" );
#endif
        if ( sv_libxml == NULL || sv_libxml == &PL_sv_undef ) {
            croak( "no XML::LibXML data found" );
        }
        node = PmmSvNode( sv_libxml );
        if ( node == NULL ) {
            croak( "no XML::LibXML data found (empty structure)" );
        }
    CODE:
        retnode = PmmCloneNode( node, deep );
        if ( retnode == NULL ) {
            croak( "Copy node failed" );
        }

        RETVAL =  PmmNodeToGdomeSv( retnode );
    OUTPUT:
        RETVAL


int
load_catalog( self, filename )
        SV * filename
    PREINIT:
        const char * fn = (const char *) Sv2C(filename, NULL);
    INIT:
        if ( fn == NULL || xmlStrlen( (xmlChar *)fn ) == 0 ) {
            croak( "cannot load catalog" );
        }
    CODE:
#ifdef LIBXML_CATALOG_ENABLED
        RETVAL = xmlLoadCatalog( fn );
#else
        XSRETURN_UNDEF;
#endif
    OUTPUT:
        RETVAL



int
_default_catalog( self, catalog )
        SV * catalog
    PREINIT:
#ifdef LIBXML_CATALOG_ENABLED
        xmlCatalogPtr catal = INT2PTR(xmlCatalogPtr,SvIV(SvRV(catalog)));
#endif
    INIT:
        if ( catal == NULL ) {
            croak( "empty catalog\n" );
        }
    CODE:
        warn( "this feature is not implemented" );
        RETVAL = 0;
    OUTPUT:
        RETVAL

SV*
_externalEntityLoader( loader )
        SV* loader
    CODE:
        {
            RETVAL = EXTERNAL_ENTITY_LOADER_FUNC;
            if(EXTERNAL_ENTITY_LOADER_FUNC == NULL)
            {
                EXTERNAL_ENTITY_LOADER_FUNC = newSVsv(loader);
            }

            if (LibXML_old_ext_ent_loader == NULL )
            {
                LibXML_old_ext_ent_loader = xmlGetExternalEntityLoader();
                xmlSetExternalEntityLoader((xmlExternalEntityLoader)LibXML_load_external_entity);
            }
        }
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::HashTable

xmlHashTablePtr
new(CLASS)
        const char * CLASS
    CODE:
		RETVAL = xmlHashCreate(8);
    OUTPUT:
        RETVAL

void
DESTROY( table )
        xmlHashTablePtr table
    CODE:
        xs_warn("DESTROY XMLHASHTABLE\n");
	PmmFreeHashTable(table);

MODULE = XML::LibXML         PACKAGE = XML::LibXML::ParserContext

void
DESTROY( self )
        SV * self
    CODE:
        xs_warn( "DROP PARSER CONTEXT!" );
        PmmContextREFCNT_dec( SvPROXYNODE( self ) );


MODULE = XML::LibXML         PACKAGE = XML::LibXML::Document

SV *
_toString(self, format=0)
        xmlDocPtr self
        int format
    PREINIT:
        xmlChar *result=NULL;
        int len=0;
        SV* internalFlag = NULL;
        int oldTagFlag = xmlSaveNoEmptyTags;
        xmlDtdPtr intSubset = NULL;
        /* PREINIT_SAVED_ERROR */
    CODE:
        RETVAL = &PL_sv_undef;
        internalFlag = get_sv("XML::LibXML::setTagCompression", 0);
        if( internalFlag ) {
            xmlSaveNoEmptyTags = SvTRUE(internalFlag);
        }

        internalFlag = get_sv("XML::LibXML::skipDTD", 0);
        if ( internalFlag && SvTRUE(internalFlag) ) {
            intSubset = xmlGetIntSubset( self );
            if ( intSubset )
                xmlUnlinkNode( INT2PTR(xmlNodePtr,intSubset) );
        }

        /* INIT_ERROR_HANDLER; */

        if ( format <= 0 ) {
            xs_warn( "use no formated toString!" );
            xmlDocDumpMemory(self, &result, &len);
        }
        else {
            int t_indent_var = xmlIndentTreeOutput;
            xs_warn( "use formated toString!" );
            xmlIndentTreeOutput = 1;
            xmlDocDumpFormatMemory( self, &result, &len, format );
            xmlIndentTreeOutput = t_indent_var;
        }

        if ( intSubset != NULL ) {
            if (self->children == NULL) {
                xmlAddChild(INT2PTR(xmlNodePtr,self), INT2PTR(xmlNodePtr,intSubset));
            }
            else {
                xmlAddPrevSibling(self->children, INT2PTR(xmlNodePtr,intSubset));
            }
        }

        xmlSaveNoEmptyTags = oldTagFlag;

        /* REPORT_ERROR(0); */

        if (result == NULL) {
            xs_warn("Failed to convert doc to string");
            XSRETURN_UNDEF;
        } else {
            /* warn("%s, %d\n",result, len); */
            RETVAL = newSVpvn( (const char *)result, len );
	    /* C2Sv( result, self->encoding ); */
            xmlFree(result);
        }
    OUTPUT:
        RETVAL

int
toFH( self, filehandler, format=0 )
        xmlDocPtr self
        SV * filehandler
        int format
    PREINIT:
        xmlOutputBufferPtr buffer;
        const xmlChar * encoding = NULL;
        xmlCharEncodingHandlerPtr handler = NULL;
        SV* internalFlag = NULL;
        int oldTagFlag = xmlSaveNoEmptyTags;
        xmlDtdPtr intSubset = NULL;
        int t_indent_var = xmlIndentTreeOutput;
        PREINIT_SAVED_ERROR
    CODE:
        internalFlag = get_sv("XML::LibXML::setTagCompression", 0);
        if( internalFlag ) {
            xmlSaveNoEmptyTags = SvTRUE(internalFlag);
        }

        internalFlag = get_sv("XML::LibXML::skipDTD", 0);
        if ( internalFlag && SvTRUE(internalFlag) ) {
            intSubset = xmlGetIntSubset( self );
            if ( intSubset )
                xmlUnlinkNode( INT2PTR(xmlNodePtr,intSubset) );
        }

        xmlRegisterDefaultOutputCallbacks();
        encoding = (self)->encoding;
        if ( encoding != NULL ) {
            if ( xmlParseCharEncoding((const char*)encoding) != XML_CHAR_ENCODING_UTF8) {
                handler = xmlFindCharEncodingHandler((const char*)encoding);
            }

        }
        else {
            xs_warn("no encoding?");
        }

        buffer = xmlOutputBufferCreateIO( (xmlOutputWriteCallback) &LibXML_output_write_handler,
                                          (xmlOutputCloseCallback)&LibXML_output_close_handler,
                                          filehandler,
                                          handler );

        if ( format <= 0 ) {
            format = 0;
            xmlIndentTreeOutput = 0;
        }
        else {
            xmlIndentTreeOutput = 1;
        }

        INIT_ERROR_HANDLER;

        RETVAL = xmlSaveFormatFileTo( buffer,
                                      self,
                                      (const char *) encoding,
                                      format);

        if ( intSubset != NULL ) {
            if (self->children == NULL) {
                xmlAddChild(INT2PTR(xmlNodePtr,self), INT2PTR(xmlNodePtr,intSubset));
            }
            else {
                xmlAddPrevSibling(self->children, INT2PTR(xmlNodePtr,intSubset));
            }
        }

        xmlIndentTreeOutput = t_indent_var;
        xmlSaveNoEmptyTags = oldTagFlag;
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(0);
    OUTPUT:
        RETVAL

int
toFile( self, filename, format=0 )
        xmlDocPtr self
        char * filename
        int format
    PREINIT:
        SV* internalFlag = NULL;
        int oldTagFlag = xmlSaveNoEmptyTags;
        PREINIT_SAVED_ERROR
    CODE:
        internalFlag = get_sv("XML::LibXML::setTagCompression", 0);
        if( internalFlag ) {
            xmlSaveNoEmptyTags = SvTRUE(internalFlag);
        }

        INIT_ERROR_HANDLER;

        if ( format <= 0 ) {
            xs_warn( "use no formated toFile!" );
            RETVAL = xmlSaveFile( filename, self );
        }
        else {
            int t_indent_var = xmlIndentTreeOutput;
            xmlIndentTreeOutput = 1;
            RETVAL =xmlSaveFormatFile( filename,
                                       self,
                                       format);
            xmlIndentTreeOutput = t_indent_var;
        }

        xmlSaveNoEmptyTags = oldTagFlag;
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(0);

        if ( RETVAL > 0 )
            RETVAL = 1;
        else
            XSRETURN_UNDEF;
    OUTPUT:
        RETVAL

SV *
toStringHTML(self)
        xmlDocPtr self
    ALIAS:
       XML::LibXML::Document::serialize_html = 1
    PREINIT:
        xmlChar *result=NULL;
        int len = 0;
        PREINIT_SAVED_ERROR
    CODE:
        PERL_UNUSED_VAR(ix);
        xs_warn( "use no formated toString!" );
        INIT_ERROR_HANDLER;
        htmlDocDumpMemory(self, &result, &len);
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(0);

        if (result == NULL) {
            XSRETURN_UNDEF;
        } else {
            /* warn("%s, %d\n",result, len); */
            RETVAL = newSVpvn((char *)result, (STRLEN)len);
            xmlFree(result);
        }
    OUTPUT:
        RETVAL


const char *
URI( self )
        xmlDocPtr self
    ALIAS:
        XML::LibXML::Document::documentURI = 1
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = (const char*)xmlStrdup(self->URL );
    OUTPUT:
        RETVAL

void
setURI( self, new_URI )
        xmlDocPtr self
        char * new_URI
    CODE:
        if (new_URI) {
            xmlFree((xmlChar*)self->URL );
            self->URL = xmlStrdup((const xmlChar*)new_URI);
        }

SV*
createDocument( CLASS, version="1.0", encoding=NULL )
        char * version
        char * encoding
    ALIAS:
        XML::LibXML::Document::new = 1
    PREINIT:
        xmlDocPtr doc=NULL;
    CODE:
        PERL_UNUSED_VAR(ix);
        doc = xmlNewDoc((const xmlChar*)version);
        if (encoding && *encoding != 0) {
            doc->encoding = (const xmlChar*)xmlStrdup((const xmlChar*)encoding);
        }
        RETVAL = PmmNodeToSv(INT2PTR(xmlNodePtr,doc),NULL);
    OUTPUT:
        RETVAL

SV*
createInternalSubset( self, Pname, extID, sysID )
        xmlDocPtr self
        SV * Pname
        SV * extID
        SV * sysID
    PREINIT:
        xmlDtdPtr dtd = NULL;
        xmlChar * name = NULL;
        xmlChar * externalID = NULL;
        xmlChar * systemID = NULL;
    CODE:
        name = Sv2C( Pname, NULL );
        if ( name == NULL ) {
            XSRETURN_UNDEF;
        }

        externalID = Sv2C(extID, NULL);
        systemID   = Sv2C(sysID, NULL);

        dtd = xmlCreateIntSubset( self, name, externalID, systemID );
        xmlFree(externalID);
        xmlFree(systemID);
        xmlFree(name);
        if ( dtd ) {
            RETVAL = PmmNodeToSv( INT2PTR(xmlNodePtr,dtd), PmmPROXYNODE(self) );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
createExternalSubset( self, Pname, extID, sysID )
        xmlDocPtr self
        SV * Pname
        SV * extID
        SV * sysID
    PREINIT:
        xmlDtdPtr dtd = NULL;
        xmlChar * name = NULL;
        xmlChar * externalID = NULL;
        xmlChar * systemID = NULL;
    CODE:
        name = Sv2C( Pname, NULL );
        if ( name == NULL ) {
            XSRETURN_UNDEF;
        }

        externalID = Sv2C(extID, NULL);
        systemID   = Sv2C(sysID, NULL);

        dtd = xmlNewDtd( self, name, externalID, systemID );

        xmlFree(externalID);
        xmlFree(systemID);
        xmlFree(name);
        if ( dtd ) {
            RETVAL = PmmNodeToSv( (xmlNodePtr)dtd, PmmPROXYNODE(self) );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
createDTD( self, Pname, extID, sysID )
        xmlDocPtr self
        SV * Pname
        SV * extID
        SV * sysID
    PREINIT:
        xmlDtdPtr dtd = NULL;
        xmlChar * name = NULL;
        xmlChar * externalID = NULL;
        xmlChar * systemID = NULL;
    CODE:
        name = Sv2C( Pname, NULL );
        if ( name == NULL ) {
            XSRETURN_UNDEF;
        }

        externalID = Sv2C(extID, NULL);
        systemID   = Sv2C(sysID, NULL);

        dtd = xmlNewDtd( NULL, name, externalID, systemID );
        dtd->doc = self;

        xmlFree(externalID);
        xmlFree(systemID);
        xmlFree(name);
        if ( dtd ) {
            RETVAL = PmmNodeToSv( (xmlNodePtr)dtd, PmmPROXYNODE(self) );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
createDocumentFragment( self )
        xmlDocPtr self
    CODE:
        RETVAL = PmmNodeToSv(xmlNewDocFragment(self), PmmPROXYNODE(self));
    OUTPUT:
        RETVAL

SV*
createElement( self, name )
        xmlDocPtr self
        SV* name
    PREINIT:
        xmlNodePtr newNode;
        xmlChar * elname = NULL;
        ProxyNodePtr docfrag = NULL;
    CODE:
        elname = nodeSv2C( name , (xmlNodePtr) self);
        if ( !LibXML_test_node_name( elname ) ) {
            xmlFree( elname );
            croak( "bad name" );
        }

        newNode = xmlNewNode(NULL , elname);
        xmlFree(elname);
        if ( newNode != NULL ) {
            docfrag = PmmNewFragment( self );
            newNode->doc = self;
            xmlAddChild(PmmNODE(docfrag), newNode);
            RETVAL = PmmNodeToSv(newNode,docfrag);
        }
        else {
            xs_warn( "no node created!" );
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
createRawElement( self, name )
        xmlDocPtr self
        SV* name
    PREINIT:
        xmlNodePtr newNode;
        xmlChar * elname = NULL;
        ProxyNodePtr docfrag = NULL;
    CODE:
        elname = nodeSv2C( name , (xmlNodePtr) self);
        if ( !elname || xmlStrlen(elname) <= 0 ) {
            xmlFree( elname );
            croak( "bad name" );
        }

        newNode = xmlNewDocNode(self,NULL , elname, NULL);
        xmlFree(elname);
        if ( newNode != NULL ) {
            docfrag = PmmNewFragment( self );
            xmlAddChild(PmmNODE(docfrag), newNode);
            RETVAL = PmmNodeToSv(newNode,docfrag);
        }
        else {
            xs_warn( "no node created!" );
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
createElementNS( self, nsURI, name )
        xmlDocPtr self
        SV * nsURI
        SV * name
    PREINIT:
        xmlChar * ename        = NULL;
        xmlChar * prefix       = NULL;
        xmlChar * localname    = NULL;
        xmlChar * eURI         = NULL;
        xmlNsPtr ns            = NULL;
        ProxyNodePtr docfrag   = NULL;
        xmlNodePtr newNode     = NULL;
    CODE:
        ename = nodeSv2C( name , (xmlNodePtr) self );
        if ( !LibXML_test_node_name( ename ) ) {
            xmlFree( ename );
            croak( "bad name" );
        }

        eURI  = Sv2C( nsURI , NULL );

        if ( eURI != NULL && xmlStrlen(eURI)!=0 ){
            localname = xmlSplitQName2(ename, &prefix);
            if ( localname == NULL ) {
                localname = xmlStrdup( ename );
            }

			ns = xmlNewNs( NULL, eURI, prefix );
            newNode = xmlNewDocNode( self, ns, localname, NULL );
			newNode->nsDef = ns;

            xmlFree(localname);
        }
        else {
            xs_warn( " ordinary element " );
            /* ordinary element */
            localname = ename;

            newNode = xmlNewDocNode( self, NULL , localname, NULL );
        }

        docfrag = PmmNewFragment( self );
        xmlAddChild(PmmNODE(docfrag), newNode);
        RETVAL = PmmNodeToSv(newNode, docfrag);

        if ( prefix != NULL ) {
            xmlFree(prefix);
        }
        if ( eURI != NULL ) {
            xmlFree(eURI);
        }
        xmlFree(ename);
    OUTPUT:
        RETVAL

SV*
createRawElementNS( self, nsURI, name )
        xmlDocPtr self
        SV * nsURI
        SV * name
    PREINIT:
        xmlChar * ename        = NULL;
        xmlChar * prefix       = NULL;
        xmlChar * localname    = NULL;
        xmlChar * eURI         = NULL;
        xmlNsPtr ns            = NULL;
        ProxyNodePtr docfrag   = NULL;
        xmlNodePtr newNode     = NULL;
    CODE:
        ename = nodeSv2C( name , (xmlNodePtr) self );
        if ( !LibXML_test_node_name( ename ) ) {
            xmlFree( ename );
            croak( "bad name" );
        }

        eURI  = Sv2C( nsURI , NULL );

        if ( eURI != NULL && xmlStrlen(eURI)!=0 ){
            localname = xmlSplitQName2(ename, &prefix);
            if ( localname == NULL ) {
                localname = xmlStrdup( ename );
            }

            newNode = xmlNewDocNode( self,NULL , localname, NULL );

            ns = xmlSearchNsByHref( self, newNode, eURI );
            if ( ns == NULL ) {
                /* create a new NS if the NS does not already exists */
                ns = xmlNewNs(newNode, eURI , prefix );
            }

            if ( ns == NULL ) {
                xmlFreeNode( newNode );
                xmlFree(eURI);
                xmlFree(localname);
                if ( prefix != NULL ) {
                    xmlFree(prefix);
                }
                xmlFree(ename);
                XSRETURN_UNDEF;
            }

            xmlFree(localname);
        }
        else {
            xs_warn( " ordinary element " );
            /* ordinary element */
            localname = ename;

            newNode = xmlNewDocNode( self, NULL , localname, NULL );
        }

        xmlSetNs(newNode, ns);
        docfrag = PmmNewFragment( self );
        xmlAddChild(PmmNODE(docfrag), newNode);
        RETVAL = PmmNodeToSv(newNode, docfrag);

        if ( prefix != NULL ) {
            xmlFree(prefix);
        }
        if ( eURI != NULL ) {
            xmlFree(eURI);
        }
        xmlFree(ename);
    OUTPUT:
        RETVAL

SV *
createTextNode( self, content )
        xmlDocPtr self
        SV * content
    PREINIT:
        xmlNodePtr newNode;
        xmlChar * elname = NULL;
        ProxyNodePtr docfrag = NULL;
    CODE:
        elname = nodeSv2C( content , (xmlNodePtr) self );
        if ( elname != NULL || xmlStrlen(elname) > 0 ) {
            newNode = xmlNewDocText( self, elname );
            xmlFree(elname);
            if ( newNode != NULL ) {
                docfrag = PmmNewFragment( self );
                newNode->doc = self;
                xmlAddChild(PmmNODE(docfrag), newNode);
                RETVAL = PmmNodeToSv(newNode,docfrag);
            }
            else {
                xs_warn( "no node created!" );
                XSRETURN_UNDEF;
            }
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV *
createComment( self , content )
        xmlDocPtr self
        SV * content
    PREINIT:
        xmlNodePtr newNode;
        xmlChar * elname = NULL;
        ProxyNodePtr docfrag = NULL;
    CODE:
        elname = nodeSv2C( content , (xmlNodePtr) self );
        if ( elname != NULL || xmlStrlen(elname) > 0 ) {
            newNode = xmlNewDocComment( self, elname );
            xmlFree(elname);
            if ( newNode != NULL ) {
                docfrag = PmmNewFragment( self );
                newNode->doc = self;
                xmlAddChild(PmmNODE(docfrag), newNode);
                xs_warn( newNode->name );
                RETVAL = PmmNodeToSv(newNode,docfrag);
            }
            else {
                xs_warn( "no node created!" );
                XSRETURN_UNDEF;
            }
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV *
createCDATASection( self, content )
        xmlDocPtr self
        SV * content
    PREINIT:
        xmlNodePtr newNode;
        xmlChar * elname = NULL;
        ProxyNodePtr docfrag = NULL;
    CODE:
        elname = nodeSv2C( content , (xmlNodePtr)self );
        if ( elname != NULL || xmlStrlen(elname) > 0 ) {
            newNode = xmlNewCDataBlock( self, elname, xmlStrlen(elname) );
            xmlFree(elname);
            if ( newNode != NULL ) {
                docfrag = PmmNewFragment( self );
                newNode->doc = self;
                xmlAddChild(PmmNODE(docfrag), newNode);
                xs_warn( "[CDATA section]" );
                RETVAL = PmmNodeToSv(newNode,docfrag);
            }
            else {
                xs_warn( "no node created!" );
                XSRETURN_UNDEF;
            }
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
createEntityReference( self , pname )
        xmlDocPtr self
        SV * pname
    PREINIT:
        xmlNodePtr newNode;
        xmlChar * name = Sv2C( pname, NULL );
        ProxyNodePtr docfrag = NULL;
    CODE:
        if ( name == NULL ) {
            XSRETURN_UNDEF;
        }
        newNode = xmlNewReference( self, name );
        xmlFree(name);
        if ( newNode == NULL ) {
            XSRETURN_UNDEF;
        }
        docfrag = PmmNewFragment( self );
        xmlAddChild(PmmNODE(docfrag), newNode);
        RETVAL = PmmNodeToSv( newNode, docfrag );
    OUTPUT:
        RETVAL

SV*
createAttribute( self, pname, pvalue=&PL_sv_undef )
        xmlDocPtr self
        SV * pname
        SV * pvalue
    PREINIT:
        xmlChar * name = NULL;
        xmlChar * value = NULL;
        xmlAttrPtr newAttr = NULL;
        xmlChar * buffer = NULL;
    CODE:
        name = nodeSv2C( pname , (xmlNodePtr) self );
        if ( !LibXML_test_node_name( name ) ) {
            xmlFree(name);
            XSRETURN_UNDEF;
        }

        value = nodeSv2C( pvalue , (xmlNodePtr) self );
        /* unlike xmlSetProp, xmlNewDocProp does not encode entities in value */
        buffer = xmlEncodeEntitiesReentrant(self, value);
        newAttr = xmlNewDocProp( self, name, buffer );
        RETVAL = PmmNodeToSv((xmlNodePtr)newAttr, PmmPROXYNODE(self));

        xmlFree(name);
        xmlFree(buffer);
        if ( value ) {
            xmlFree(value);
        }
    OUTPUT:
        RETVAL

SV*
createAttributeNS( self, URI, pname, pvalue=&PL_sv_undef )
        xmlDocPtr self
        SV * URI
        SV * pname
        SV * pvalue
    PREINIT:
        xmlChar * name = NULL;
        xmlChar * value = NULL;
        xmlChar * prefix = NULL;
        const xmlChar * pchar = NULL;
        xmlChar * localname = NULL;
        xmlChar * nsURI = NULL;
        xmlAttrPtr newAttr = NULL;
        xmlNsPtr ns = NULL;
    CODE:
        name = nodeSv2C( pname , (xmlNodePtr) self );
        if ( !LibXML_test_node_name( name ) ) {
            xmlFree(name);
            XSRETURN_UNDEF;
        }

        nsURI = Sv2C( URI , NULL );
        value = nodeSv2C( pvalue, (xmlNodePtr) self  );

        if ( nsURI != NULL && xmlStrlen(nsURI) > 0 ) {
            xmlNodePtr root = xmlDocGetRootElement(self );
            if ( root ) {
                pchar = xmlStrchr(name, ':');
                if ( pchar != NULL ) {
                    localname = xmlSplitQName2(name, &prefix);
                }
                else {
                    localname = xmlStrdup( name );
                }
                ns = xmlSearchNsByHref( self, root, nsURI );
                if ( ns == NULL ) {
                    /* create a new NS if the NS does not already exists */
                    ns = xmlNewNs(root, nsURI , prefix );
                }

                if ( ns == NULL ) {
                    xmlFree(nsURI);
                    xmlFree(localname);
                    if ( prefix ) {
                        xmlFree(prefix);
                    }
                    xmlFree(name);
                    if ( value ) {
                        xmlFree(value);
                    }
                    XSRETURN_UNDEF;
                }

                newAttr = xmlNewDocProp( self, localname, value );
                xmlSetNs((xmlNodePtr)newAttr, ns);

                RETVAL = PmmNodeToSv((xmlNodePtr)newAttr, PmmPROXYNODE(self) );

                xmlFree(nsURI);
                xmlFree(name);
                if ( prefix ) {
                    xmlFree(prefix);
                }
                xmlFree(localname);
                if ( value ) {
                    xmlFree(value);
                }
            }
            else {
                croak( "can't create a new namespace on an attribute!" );
                xmlFree(name);
                if ( value ) {
                    xmlFree(value);
                }
                XSRETURN_UNDEF;
            }
        }
        else {
            xmlChar *buffer;
            /* unlike xmlSetProp, xmlNewDocProp does not encode entities in value */
            buffer = xmlEncodeEntitiesReentrant(self, value);
            newAttr = xmlNewDocProp( self, name, buffer );
            RETVAL = PmmNodeToSv((xmlNodePtr)newAttr,PmmPROXYNODE(self));
            xmlFree(name);
            xmlFree(buffer);
            if ( value ) {
                xmlFree(value);
            }
        }
    OUTPUT:
        RETVAL

SV*
createProcessingInstruction(self, name, value=&PL_sv_undef)
        xmlDocPtr self
        SV * name
        SV * value
    ALIAS:
        createPI = 1
    PREINIT:
        xmlChar * n = NULL;
        xmlChar * v = NULL;
        xmlNodePtr newNode = NULL;
        ProxyNodePtr docfrag = NULL;
    CODE:
        PERL_UNUSED_VAR(ix);
        n = nodeSv2C(name, (xmlNodePtr)self);
        if ( !n ) {
            XSRETURN_UNDEF;
        }
        v = nodeSv2C(value, (xmlNodePtr)self);
        newNode = xmlNewPI(n,v);
        xmlFree(v);
        xmlFree(n);
	if ( newNode != NULL ) {
 	   docfrag = PmmNewFragment( self );
           newNode->doc = self;
	   xmlAddChild(PmmNODE(docfrag), newNode);
	   RETVAL = PmmNodeToSv(newNode,docfrag);
	} else {
 	   xs_warn( "no node created!" );
 	   XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

void
_setDocumentElement( self , proxy )
        xmlDocPtr self
        SV * proxy
    PREINIT:
        xmlNodePtr elem, oelem;
    INIT:
        elem = PmmSvNode(proxy);
        if ( elem == NULL ) {
            XSRETURN_UNDEF;
        }
    CODE:
        /* please correct me if i am wrong: the document element HAS to be
         * an ELEMENT NODE
         */
        if ( elem->type == XML_ELEMENT_NODE ) {
            if ( self != elem->doc ) {
	        domImportNode( self, elem, 1, 1 );
            }

            oelem = xmlDocGetRootElement( self );
            if ( oelem == NULL || oelem->_private == NULL ) {
                xmlDocSetRootElement( self, elem );
            }
            else {
                ProxyNodePtr docfrag = PmmNewFragment( self );
                xmlReplaceNode( oelem, elem );
                xmlAddChild( PmmNODE(docfrag), oelem );
                PmmFixOwner( ((ProxyNodePtr)oelem->_private), docfrag);
            }

            if ( elem->_private != NULL ) {
                PmmFixOwner( SvPROXYNODE(proxy), PmmPROXYNODE(self));
            }
        } else {
            croak("setDocumentElement: ELEMENT node required");
        }

SV *
documentElement( self )
        xmlDocPtr self
    ALIAS:
        XML::LibXML::Document::getDocumentElement = 1
    PREINIT:
        xmlNodePtr elem;
    CODE:
        PERL_UNUSED_VAR(ix);
        elem = xmlDocGetRootElement( self );
        if ( elem ) {
            RETVAL = PmmNodeToSv(elem, PmmPROXYNODE(self));
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV *
externalSubset( self )
        xmlDocPtr self
    PREINIT:
        xmlDtdPtr dtd;
    CODE:
        if ( self->extSubset == NULL ) {
            XSRETURN_UNDEF;
        }

        dtd = self->extSubset;
        RETVAL = PmmNodeToSv((xmlNodePtr)dtd, PmmPROXYNODE(self));
    OUTPUT:
        RETVAL

SV *
internalSubset( self )
        xmlDocPtr self
    PREINIT:
        xmlDtdPtr dtd;
    CODE:
        if ( self->intSubset == NULL ) {
            XSRETURN_UNDEF;
        }

        dtd = self->intSubset;
RETVAL = PmmNodeToSv(INT2PTR(xmlNodePtr,dtd), PmmPROXYNODE(self));
    OUTPUT:
        RETVAL

void
setExternalSubset( self, extdtd )
        xmlDocPtr self
        SV * extdtd
    PREINIT:
        xmlDtdPtr dtd = NULL;
        xmlDtdPtr olddtd = NULL;
    INIT:
        dtd = (xmlDtdPtr)PmmSvNode(extdtd);
        if ( dtd == NULL ) {
            croak( "lost DTD node" );
        }
    CODE:
        if ( dtd && dtd != self->extSubset ) {
            if ( dtd->doc == NULL ) {
                xmlSetTreeDoc( (xmlNodePtr) dtd, self );
            } else if ( dtd->doc != self ) {
	        domImportNode( self, (xmlNodePtr) dtd,1,1);
            }

            if ( dtd == self->intSubset ) {
                xmlUnlinkNode( (xmlNodePtr)dtd );
                self->intSubset = NULL;
            }

            olddtd = self->extSubset;
            if ( olddtd && olddtd->_private == NULL ) {
                xmlFreeDtd( olddtd );
            }
            self->extSubset = dtd;
        }

void
setInternalSubset( self, extdtd )
        xmlDocPtr self
        SV * extdtd
    PREINIT:
        xmlDtdPtr dtd = NULL;
        xmlDtdPtr olddtd = NULL;
    INIT:
        dtd = (xmlDtdPtr)PmmSvNode(extdtd);
        if ( dtd == NULL ) {
            croak( "lost DTD node" );
        }
    CODE:
        if ( dtd && dtd != self->intSubset ) {
            if ( dtd->doc != self ) {
                croak( "can't import DTDs" );
                domImportNode( self, (xmlNodePtr) dtd,1,1);
            }

            if ( dtd == self->extSubset ) {
                self->extSubset = NULL;
            }

            olddtd = xmlGetIntSubset( self );
            if( olddtd ) {
                xmlReplaceNode( (xmlNodePtr)olddtd, (xmlNodePtr) dtd );
                if ( olddtd->_private == NULL ) {
                    xmlFreeDtd( olddtd );
                }
            }
            else {
                if (self->children == NULL)
                    xmlAddChild((xmlNodePtr) self, (xmlNodePtr) dtd);
                else
                    xmlAddPrevSibling(self->children, (xmlNodePtr) dtd);
            }
            self->intSubset = dtd;
        }

SV *
removeInternalSubset( self )
        xmlDocPtr self
    PREINIT:
        xmlDtdPtr dtd = NULL;
    CODE:
        dtd = xmlGetIntSubset(self);
        if ( !dtd ) {
            XSRETURN_UNDEF;
        }
        xmlUnlinkNode( (xmlNodePtr)dtd );
        self->intSubset = NULL;
        RETVAL = PmmNodeToSv( (xmlNodePtr)dtd, PmmPROXYNODE(self) );
    OUTPUT:
        RETVAL

SV *
removeExternalSubset( self )
        xmlDocPtr self
    PREINIT:
        xmlDtdPtr dtd = NULL;
    CODE:
        dtd = self->extSubset;
        if ( !dtd ) {
            XSRETURN_UNDEF;
        }
        self->extSubset = NULL;
        RETVAL = PmmNodeToSv( (xmlNodePtr)dtd, PmmPROXYNODE(self) );
    OUTPUT:
        RETVAL

SV *
importNode( self, node, dummy=0 )
        xmlDocPtr self
        xmlNodePtr node
        int dummy
    PREINIT:
        xmlNodePtr ret = NULL;
        ProxyNodePtr docfrag = NULL;
    CODE:
        if ( node->type == XML_DOCUMENT_NODE
             || node->type == XML_HTML_DOCUMENT_NODE ) {
            croak( "Can't import Documents!" );
            XSRETURN_UNDEF;
        }
        if (node->type == XML_DTD_NODE) {
            croak("Can't import DTD nodes");
        }

        ret = domImportNode( self, node, 0, 1 );
        if ( ret ) {
            docfrag = PmmNewFragment( self );
            xmlAddChild( PmmNODE(docfrag), ret );
            RETVAL = PmmNodeToSv( ret, docfrag);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV *
adoptNode( self, node )
        xmlDocPtr self
        xmlNodePtr node
    PREINIT:
        xmlNodePtr ret = NULL;
        ProxyNodePtr docfrag = NULL;
    CODE:
        if ( node->type == XML_DOCUMENT_NODE
             || node->type == XML_HTML_DOCUMENT_NODE ) {
            croak( "Can't adopt Documents!" );
            XSRETURN_UNDEF;
        }
        if (node->type == XML_DTD_NODE) {
            croak("Can't adopt DTD nodes");
        }

        ret = domImportNode( self, node, 1, 1 );

        if ( ret ) {
            docfrag = PmmNewFragment( self );
            RETVAL = PmmNodeToSv(node, docfrag);
            xmlAddChild( PmmNODE(docfrag), ret );
            PmmFixOwner(SvPROXYNODE(RETVAL), docfrag);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

char*
encoding( self )
        xmlDocPtr self
    ALIAS:
        XML::LibXML::Document::getEncoding    = 1
        XML::LibXML::Document::xmlEncoding    = 2
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = (char *) self->encoding;
    OUTPUT:
        RETVAL

void
setEncoding( self, encoding = NULL )
        xmlDocPtr self
        char *encoding
    PREINIT:
        int charset = XML_CHAR_ENCODING_ERROR;
    CODE:
        if ( self->encoding != NULL ) {
            xmlFree( (xmlChar*) self->encoding );
        }
        if (encoding!=NULL && strlen(encoding)) {
	  self->encoding = xmlStrdup( (const xmlChar *)encoding );
	  charset = (int)xmlParseCharEncoding( (const char*)self->encoding );
	  if ( charset <= 0 ) {
            charset = XML_CHAR_ENCODING_ERROR;
	  }
	} else {
	  self->encoding=NULL;
          charset = XML_CHAR_ENCODING_UTF8;
	}
        SetPmmNodeEncoding(self, charset);


int
standalone( self )
        xmlDocPtr self
    ALIAS:
        XML::LibXML::Document::xmlStandalone    = 1
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = self->standalone;
    OUTPUT:
        RETVAL

void
setStandalone( self, value = 0 )
        xmlDocPtr self
        int value
    CODE:
        if ( value > 0 ) {
            self->standalone = 1;
        }
        else if ( value < 0 ) {
            self->standalone = -1;
        }
        else {
            self->standalone = 0;
        }

char*
version( self )
         xmlDocPtr self
    ALIAS:
        XML::LibXML::Document::getVersion = 1
        XML::LibXML::Document::xmlVersion = 2
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = (char *) self->version;
    OUTPUT:
        RETVAL

void
setVersion( self, version )
        xmlDocPtr self
        char *version
    CODE:
        if ( self->version != NULL ) {
            xmlFree( (xmlChar*) self->version );
        }
        self->version = xmlStrdup( (const xmlChar*)version );

int
compression( self )
        xmlDocPtr self
    CODE:
        RETVAL = xmlGetDocCompressMode(self);
    OUTPUT:
        RETVAL

void
setCompression( self, zLevel )
        xmlDocPtr self
        int zLevel
    CODE:
        xmlSetDocCompressMode(self, zLevel);


int
is_valid(self, ...)
        xmlDocPtr self
    PREINIT:
        xmlValidCtxt cvp;
        xmlDtdPtr dtd = NULL;
        SV * dtd_sv;
        PREINIT_SAVED_ERROR
    CODE:
        INIT_ERROR_HANDLER;

        cvp.userData = saved_error;
        cvp.error = (xmlValidityErrorFunc)LibXML_validity_error_ctx;
        cvp.warning = (xmlValidityWarningFunc)LibXML_validity_warning_ctx;

        /* we need to initialize the node stack, because perl might
         * already have messed it up.
         */
        cvp.nodeNr = 0;
        cvp.nodeTab = NULL;
        cvp.vstateNr = 0;
        cvp.vstateTab = NULL;

        PmmClearPSVI(self);
        PmmInvalidatePSVI(self);
        if (items > 1) {
            dtd_sv = ST(1);
            if ( sv_isobject(dtd_sv) && (SvTYPE(SvRV(dtd_sv)) == SVt_PVMG) ) {
                dtd = (xmlDtdPtr)PmmSvNode(dtd_sv);
            }
            RETVAL = xmlValidateDtd(&cvp, self, dtd);
        }
        else {
            RETVAL = xmlValidateDocument(&cvp, self);
        }
        CLEANUP_ERROR_HANDLER;
        /* REPORT_ERROR(1); */
    OUTPUT:
        RETVAL

int
validate(self, ...)
        xmlDocPtr self
    PREINIT:
        xmlValidCtxt cvp;
        xmlDtdPtr dtd;
        SV * dtd_sv;
        PREINIT_SAVED_ERROR
    CODE:
        INIT_ERROR_HANDLER;

        cvp.userData = saved_error;
        cvp.error = (xmlValidityErrorFunc)LibXML_validity_error_ctx;
        cvp.warning = (xmlValidityWarningFunc)LibXML_validity_warning_ctx;
        /* we need to initialize the node stack, because perl might
         * already have messed it up.
         */
        cvp.nodeNr = 0;
        cvp.nodeTab = NULL;
        cvp.vstateNr = 0;
        cvp.vstateTab = NULL;

        PmmClearPSVI(self);
        PmmInvalidatePSVI(self);

        if (items > 1) {
            dtd_sv = ST(1);
            if ( sv_isobject(dtd_sv) && (SvTYPE(SvRV(dtd_sv)) == SVt_PVMG) ) {
                dtd = (xmlDtdPtr)PmmSvNode(dtd_sv);
            }
            else {
                CLEANUP_ERROR_HANDLER;
                croak("is_valid: argument must be a DTD object");
            }
            RETVAL = xmlValidateDtd(&cvp, self , dtd);
        }
        else {
            RETVAL = xmlValidateDocument(&cvp, self);
        }
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(RETVAL ? 1 : 0);
    OUTPUT:
        RETVAL

SV*
cloneNode( self, deep=0 )
        xmlDocPtr self
        int deep
    PREINIT:
        xmlDocPtr ret = NULL;
    CODE:
        ret = xmlCopyDoc( self, deep );
        if ( ret == NULL ) {
            XSRETURN_UNDEF;
        }
        RETVAL = PmmNodeToSv((xmlNodePtr)ret, NULL);
    OUTPUT:
        RETVAL

SV*
getElementById( self, id )
        xmlDocPtr self
        const char * id
    ALIAS:
        XML::LibXML::Document::getElementsById = 1
    PREINIT:
        xmlNodePtr elem;
        xmlAttrPtr attr;
    CODE:
        PERL_UNUSED_VAR(ix);
        if ( id != NULL ) {
            attr = xmlGetID(self, (xmlChar *) id);
            if (attr == NULL)
                elem = NULL;
            else if (attr->type == XML_ATTRIBUTE_NODE)
                elem = attr->parent;
            else if (attr->type == XML_ELEMENT_NODE)
                elem = (xmlNodePtr) attr;
            else
                elem = NULL;
            if (elem != NULL) {
                RETVAL = PmmNodeToSv(elem, PmmPROXYNODE(self));
            }
            else {
                XSRETURN_UNDEF;
            }
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

int
indexElements ( self )
        xmlDocPtr self
     CODE:
#if LIBXML_VERSION >= 20508
        RETVAL = xmlXPathOrderDocElems( self );
#else
        RETVAL = -2;
#endif
     OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Node

void
DESTROY( node )
        SV * node
    PREINIT:
        int count;
        SV *is_shared;
    CODE:
#ifdef XML_LIBXML_THREADS
    if ( (is_shared = get_sv("XML::LibXML::__threads_shared", 0)) == NULL ) {
        is_shared = &PL_sv_undef;
    }
    if ( SvTRUE(is_shared) ) {
        dSP;
        ENTER;
        SAVETMPS;
        PUSHMARK(SP);
        XPUSHs(node);
        PUTBACK;
        count = call_pv("threads::shared::is_shared", G_SCALAR);
        SPAGAIN;
        if (count != 1)
            croak("Couldn't checks if the variable is shared or not\n");
        is_shared = POPs;
        PUTBACK;
        FREETMPS;
        LEAVE;
        if (is_shared != &PL_sv_undef) {
            XSRETURN_UNDEF;
        }
    }
	if( PmmUSEREGISTRY ) {
	  SvLOCK(PROXY_NODE_REGISTRY_MUTEX);
	  PmmRegistryREFCNT_dec(SvPROXYNODE(node));
        }
#endif
        PmmREFCNT_dec(SvPROXYNODE(node));
#ifdef XML_LIBXML_THREADS
	if( PmmUSEREGISTRY )
	  SvUNLOCK(PROXY_NODE_REGISTRY_MUTEX);
#endif

SV*
nodeName( self )
        xmlNodePtr self
    ALIAS:
        XML::LibXML::Node::getName = 1
        XML::LibXML::Element::tagName = 2
    PREINIT:
        xmlChar * name = NULL;
    CODE:
        PERL_UNUSED_VAR(ix);
        name =  (xmlChar*)domName( self );
        if ( name != NULL ) {
            RETVAL = C2Sv(name,NULL);
            xmlFree( name );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
localname( self )
        xmlNodePtr self
    ALIAS:
        XML::LibXML::Node::getLocalName = 1
        XML::LibXML::Attr::name         = 2
        XML::LibXML::Node::localName    = 3
    CODE:
        PERL_UNUSED_VAR(ix);
        if (    self->type == XML_ELEMENT_NODE
             || self->type == XML_ATTRIBUTE_NODE
             || self->type == XML_ELEMENT_DECL
             || self->type == XML_ATTRIBUTE_DECL ) {
            RETVAL = C2Sv(self->name,NULL);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
prefix( self )
        xmlNodePtr self
    ALIAS:
        XML::LibXML::Node::getPrefix = 1
    CODE:
        PERL_UNUSED_VAR(ix);
        if( ( self->type == XML_ELEMENT_NODE
	    || self->type == XML_ATTRIBUTE_NODE
	    || self->type == XML_PI_NODE )
            && self->ns != NULL
            && self->ns->prefix != NULL ) {
            RETVAL = C2Sv(self->ns->prefix, NULL);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
namespaceURI( self )
        xmlNodePtr self
    ALIAS:
        getNamespaceURI = 1
    PREINIT:
        xmlChar * nsURI;
    CODE:
        PERL_UNUSED_VAR(ix);
        if ( ( self->type == XML_ELEMENT_NODE
	    || self->type == XML_ATTRIBUTE_NODE
	    || self->type == XML_PI_NODE )
	     && self->ns != NULL
             && self->ns->href != NULL ) {
            nsURI =  xmlStrdup(self->ns->href);
            RETVAL = C2Sv( nsURI, NULL );
            xmlFree( nsURI );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL


SV*
lookupNamespaceURI( self, svprefix=&PL_sv_undef )
        xmlNodePtr self
        SV * svprefix
    PREINIT:
        xmlChar * nsURI;
        xmlChar * prefix = NULL;
        xmlNsPtr ns;
    CODE:
        prefix = nodeSv2C( svprefix , self );
        if ( prefix != NULL && xmlStrlen(prefix) == 0) {
            xmlFree( prefix );
            prefix = NULL;
        }
        ns = xmlSearchNs( self->doc, self, prefix );
        if ( prefix != NULL) {
            xmlFree( prefix );
	}
        if ( ns != NULL ) {
	  nsURI = xmlStrdup(ns->href);
	  RETVAL = C2Sv( nsURI, NULL );
	  xmlFree( nsURI );
	}
	else {
	  XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
lookupNamespacePrefix( self, svuri )
        xmlNodePtr self
        SV * svuri
    PREINIT:
        xmlChar * nsprefix;
        xmlChar * href = NULL;
    CODE:
        href = nodeSv2C( svuri , self );
        if ( href != NULL && xmlStrlen(href) > 0) {
            xmlNsPtr ns = xmlSearchNsByHref( self->doc, self, href );
            xmlFree( href );
            if ( ns != NULL ) {
		    if ( ns->prefix != NULL ) {
			  nsprefix = xmlStrdup( ns->prefix );
			  RETVAL = C2Sv( nsprefix, NULL );
			  xmlFree(nsprefix);
		    } else {
			  RETVAL = newSVpv("",0);
		    }
            }
            else {
                XSRETURN_UNDEF;
            }
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL


void
setNodeName( self , value )
        xmlNodePtr self
        SV* value
    ALIAS:
        setName = 1
    PREINIT:
        xmlChar* string;
        xmlChar* localname;
        xmlChar* prefix;
    CODE:
        PERL_UNUSED_VAR(ix);
        string = nodeSv2C( value , self );
        if ( !LibXML_test_node_name( string ) ) {
            xmlFree(string);
            croak( "bad name" );
        }
        if( ( self->type == XML_ELEMENT_NODE
	    || self->type == XML_ATTRIBUTE_NODE
	    || self->type == XML_PI_NODE)
	    && self->ns ){
            localname = xmlSplitQName2(string, &prefix);
	    if ( localname == NULL ) {
	      localname = xmlStrdup( string );
	    }
            xmlNodeSetName(self, localname );
            xmlFree(localname);
            xmlFree(prefix);
        }
        else {
            xs_warn("node name normal\n");
            xmlNodeSetName(self, string );
        }
        xmlFree(string);

void
setRawName( self, value )
        xmlNodePtr self
        SV * value
    PREINIT:
        xmlChar* string;
        xmlChar* localname;
        xmlChar* prefix;
    CODE:
        string = nodeSv2C( value , self );
        if ( !string || xmlStrlen( string) <= 0 ) {
            xmlFree(string);
            XSRETURN_UNDEF;
        }
        if( ( self->type == XML_ELEMENT_NODE
	     || self->type == XML_ATTRIBUTE_NODE
	     || self->type == XML_PI_NODE)
	    && self->ns ){
            localname = xmlSplitQName2(string, &prefix);
            xmlNodeSetName(self, localname );
            xmlFree(localname);
            xmlFree(prefix);
        }
        else {
            xmlNodeSetName(self, string );
        }
        xmlFree(string);


SV*
nodeValue( self, useDomEncoding = &PL_sv_undef )
        xmlNodePtr self
        SV * useDomEncoding
    ALIAS:
        XML::LibXML::Attr::value     = 1
        XML::LibXML::Attr::getValue  = 2
        XML::LibXML::Text::data      = 3
        XML::LibXML::Node::getValue  = 4
        XML::LibXML::Node::getData   = 5
    PREINIT:
        xmlChar * content = NULL;
    CODE:
        PERL_UNUSED_VAR(ix);
        content = domGetNodeValue( self );

        if ( content != NULL ) {
            if ( SvTRUE(useDomEncoding) ) {
                RETVAL = nodeC2Sv(content, self);
            }
            else {
                RETVAL = C2Sv(content, NULL);
            }
            xmlFree(content);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

int
nodeType( self )
        xmlNodePtr self
    ALIAS:
        XML::LibXML::Node::getType = 1
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = self->type;
    OUTPUT:
        RETVAL

SV*
parentNode( self )
        xmlNodePtr self
    ALIAS:
        XML::LibXML::Attr::ownerElement    = 1
        XML::LibXML::Node::getParentNode   = 2
        XML::LibXML::Attr::getOwnerElement = 3
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = PmmNodeToSv( self->parent,
                              PmmOWNERPO( PmmPROXYNODE(self) ) );
    OUTPUT:
        RETVAL

SV*
nextSibling( self )
        xmlNodePtr self
    ALIAS:
        getNextSibling = 1
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = PmmNodeToSv( self->next,
                              PmmOWNERPO(PmmPROXYNODE(self)) );
    OUTPUT:
        RETVAL

SV*
nextNonBlankSibling( self )
        xmlNodePtr self
    PREINIT:
        xmlNodePtr next;
    CODE:
        next = self->next;
        while (next != NULL && xmlIsBlankNode(next))
          next = next->next;
        RETVAL = PmmNodeToSv( next,
                              PmmOWNERPO(PmmPROXYNODE(self)) );
    OUTPUT:
        RETVAL


SV*
previousSibling( self )
        xmlNodePtr self
    ALIAS:
        getPreviousSibling = 1
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = PmmNodeToSv( self->prev,
                              PmmOWNERPO( PmmPROXYNODE(self) ) );
    OUTPUT:
        RETVAL

SV*
previousNonBlankSibling( self )
        xmlNodePtr self
    PREINIT:
        xmlNodePtr prev;
    CODE:
        prev = self->prev;
        while (prev != NULL && xmlIsBlankNode(prev))
          prev = prev->prev;
        RETVAL = PmmNodeToSv( prev,
                              PmmOWNERPO(PmmPROXYNODE(self)) );
    OUTPUT:
        RETVAL


void
_childNodes( self, only_nonblank = 0 )
        xmlNodePtr self
        int only_nonblank
    ALIAS:
        XML::LibXML::Node::getChildnodes = 1
    PREINIT:
        xmlNodePtr cld;
        SV * element;
        int len = 0;
        int wantarray = GIMME_V;
    PPCODE:
        PERL_UNUSED_VAR(ix);
        if ( self->type != XML_ATTRIBUTE_NODE ) {
            cld = self->children;
            xs_warn("childnodes start");
            while ( cld ) {
	        if ( !(only_nonblank && xmlIsBlankNode(cld)) ) {
                  if( wantarray != G_SCALAR ) {
                      element = PmmNodeToSv(cld, PmmOWNERPO(PmmPROXYNODE(self)) );
                      XPUSHs(sv_2mortal(element));
                  }
                  len++;
                }
                cld = cld->next;
            }
        }
        if ( wantarray == G_SCALAR ) {
            XPUSHs(sv_2mortal(newSViv(len)) );
        }

void
_getChildrenByTagNameNS( self, namespaceURI, node_name )
        xmlNodePtr self
        SV * namespaceURI
        SV * node_name
    PREINIT:
        xmlChar * name;
        xmlChar * nsURI;
        xmlNodePtr cld;
        SV * element;
        int len = 0;
	int name_wildcard = 0;
	int ns_wildcard = 0;
        int wantarray = GIMME_V;
    PPCODE:
        name = nodeSv2C(node_name, self );
        nsURI = nodeSv2C(namespaceURI, self );

        if ( nsURI != NULL ) {
            if (xmlStrlen(nsURI) == 0 ) {
                xmlFree(nsURI);
                nsURI = NULL;
            } else if (xmlStrcmp( nsURI, (xmlChar *)"*" )==0) {
                ns_wildcard = 1;
            }
        }
        if ( name !=NULL && xmlStrcmp( name, (xmlChar *)"*" ) == 0) {
            name_wildcard = 1;
        }
        if ( self->type != XML_ATTRIBUTE_NODE ) {
            cld = self->children;
            xs_warn("childnodes start");
            while ( cld ) {
	      if (((name_wildcard && (cld->type == XML_ELEMENT_NODE)) ||
		   xmlStrcmp( name, cld->name ) == 0)
		   && (ns_wildcard ||
		       (cld->ns != NULL &&
                        xmlStrcmp(nsURI,cld->ns->href) == 0 ) ||
                       (cld->ns == NULL && nsURI == NULL))) {
                if( wantarray != G_SCALAR ) {
                    element = PmmNodeToSv(cld, PmmOWNERPO(PmmPROXYNODE(self)) );
                    XPUSHs(sv_2mortal(element));
                }
                len++;
	      }
	      cld = cld->next;
            }
        }
        if ( wantarray == G_SCALAR ) {
            XPUSHs(sv_2mortal(newSViv(len)) );
        }
        xmlFree(name);
        if (nsURI) xmlFree(nsURI);

SV*
firstChild( self )
        xmlNodePtr self
    ALIAS:
        getFirstChild = 1
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = PmmNodeToSv( self->children,
                              PmmOWNERPO( PmmPROXYNODE(self) ) );
    OUTPUT:
        RETVAL

SV*
firstNonBlankChild( self )
        xmlNodePtr self
    PREINIT:
	xmlNodePtr child;
    CODE:
	child = self->children;
        while (child !=NULL && xmlIsBlankNode(child))
	  child = child->next;
        RETVAL = PmmNodeToSv( child,
                              PmmOWNERPO( PmmPROXYNODE(self) ) );
    OUTPUT:
        RETVAL

SV*
lastChild( self )
        xmlNodePtr self
    ALIAS:
        getLastChild = 1
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = PmmNodeToSv( self->last,
                              PmmOWNERPO( PmmPROXYNODE(self) ) );
    OUTPUT:
        RETVAL

void
_attributes( self )
        xmlNodePtr self
    ALIAS:
        XML::LibXML::Node::getAttributes = 1
    PREINIT:
        xmlAttrPtr attr = NULL;
        xmlNsPtr ns = NULL;
        SV * element;
        int len=0;
        int wantarray = GIMME_V;
    PPCODE:
        PERL_UNUSED_VAR(ix);
        if ( self->type != XML_ATTRIBUTE_NODE
             && self->type != XML_DTD_NODE ) {
            attr = self->properties;
            while ( attr != NULL ) {
                if ( wantarray != G_SCALAR ) {
                    element = PmmNodeToSv((xmlNodePtr)attr,
                                           PmmOWNERPO(PmmPROXYNODE(self)) );
                    XPUSHs(sv_2mortal(element));
                }
                attr = attr->next;
                len++;
            }
	    if (self->type == XML_ELEMENT_NODE) {
	      ns = self->nsDef;
	      while ( ns != NULL ) {
                const char * CLASS = "XML::LibXML::Namespace";
                if ( wantarray != G_SCALAR ) {
                    /* namespace handling is kinda odd:
                     * as soon we have a namespace isolated from its
                     * owner, we loose the context. therefore it is
                     * forbidden to access the NS information directly.
                     * instead the use will receive a copy of the real
                     * namespace, that can be destroied and is not
                     * bound to a document.
                     *
                     * this avoids segfaults in the end.
                     */
			  if ((ns->prefix != NULL || ns->href != NULL)) {
				xmlNsPtr tns = xmlCopyNamespace(ns);
				if ( tns != NULL ) {
				    element = sv_newmortal();
				    XPUSHs(sv_setref_pv( element,
								 (char *)CLASS,
								 (void*)tns));
				}
			  }
                }
                ns = ns->next;
                len++;
	      }
	    }
        }
        if( wantarray == G_SCALAR ) {
            XPUSHs( sv_2mortal(newSViv(len)) );
        }

int
hasChildNodes( self )
        xmlNodePtr self
    CODE:
        if ( self->type == XML_ATTRIBUTE_NODE ) {
            RETVAL = 0;
        }
        else {
            RETVAL =  self->children ? 1 : 0 ;
        }
    OUTPUT:
        RETVAL

int
hasAttributes( self )
        xmlNodePtr self
    CODE:
        if ( self->type == XML_ATTRIBUTE_NODE
             || self->type == XML_DTD_NODE ) {
            RETVAL = 0;
        }
        else {
            RETVAL =  self->properties ? 1 : 0 ;
        }
    OUTPUT:
        RETVAL

SV*
ownerDocument( self )
        xmlNodePtr self
    ALIAS:
        XML::LibXML::Node::getOwnerDocument = 1
    CODE:
        PERL_UNUSED_VAR(ix);
        xs_warn( "GET OWNERDOC\n" );
        if( self != NULL
            && self->doc != NULL ){
            RETVAL = PmmNodeToSv((xmlNodePtr)(self->doc), NULL);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
ownerNode( self )
        xmlNodePtr self
    ALIAS:
        XML::LibXML::Node::getOwner = 1
        XML::LibXML::Node::getOwnerElement = 2
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = PmmNodeToSv(PmmNODE(PmmOWNERPO(PmmPROXYNODE(self))), NULL);
    OUTPUT:
        RETVAL


void
normalize( self )
        xmlNodePtr self
    CODE:
        domNodeNormalize( self );


SV*
insertBefore( self, nNode, refNode )
        xmlNodePtr self
        xmlNodePtr nNode
        SV * refNode
    PREINIT:
        xmlNodePtr oNode=NULL, rNode;
    INIT:
        oNode = PmmSvNode(refNode);
    CODE:
        rNode = domInsertBefore( self, nNode, oNode );
        if ( rNode != NULL ) {
            RETVAL = PmmNodeToSv( rNode,
                                  PmmOWNERPO(PmmPROXYNODE(self)) );
            if (rNode->type == XML_DTD_NODE) {
                LibXML_set_int_subset(self->doc, rNode);
            }
            PmmFixOwner(PmmPROXYNODE(rNode), PmmOWNERPO(PmmPROXYNODE(self)));
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
insertAfter( self, nNode, refNode )
        xmlNodePtr self
        xmlNodePtr nNode
        SV* refNode
    PREINIT:
        xmlNodePtr oNode = NULL, rNode;
    INIT:
        oNode = PmmSvNode(refNode);
    CODE:
        rNode = domInsertAfter( self, nNode, oNode );
        if ( rNode != NULL ) {
            RETVAL = PmmNodeToSv( rNode,
                                  PmmOWNERPO(PmmPROXYNODE(self)) );
            if (rNode->type == XML_DTD_NODE) {
                LibXML_set_int_subset(self->doc, rNode);
            }
            PmmFixOwner(PmmPROXYNODE(rNode), PmmOWNERPO(PmmPROXYNODE(self)));
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
replaceChild( self, nNode, oNode )
        xmlNodePtr self
        xmlNodePtr nNode
        xmlNodePtr oNode
    PREINIT:
        xmlNodePtr ret = NULL;
    CODE:
        // if newNode == oldNode or self == newNode then do nothing, just return nNode.
        if (nNode == oNode || self == nNode ) {
            ret = nNode;
            RETVAL = PmmNodeToSv(ret, PmmOWNERPO(PmmPROXYNODE(ret)));
        }
        else{
            if ( self->type == XML_DOCUMENT_NODE ) {
                switch ( nNode->type ) {
                    case XML_ELEMENT_NODE:
                        warn("replaceChild with an element on a document node not supported yet!");
                        XSRETURN_UNDEF;
                        break;
                    case XML_DOCUMENT_FRAG_NODE:
                        warn("replaceChild with a document fragment node on a document node not supported yet!");
                        XSRETURN_UNDEF;
                        break;
                    case XML_TEXT_NODE:
                    case XML_CDATA_SECTION_NODE:
                        warn("replaceChild with a text node not supported on a document node!");
                        XSRETURN_UNDEF;
                        break;
                    default:
                        break;
                }
            }
            ret = domReplaceChild( self, nNode, oNode );
            if (ret == NULL) {
                XSRETURN_UNDEF;
            }
            else {
                LibXML_reparent_removed_node(ret);
                RETVAL = PmmNodeToSv(ret, PmmOWNERPO(PmmPROXYNODE(ret)));
                if (nNode->type == XML_DTD_NODE) {
                    LibXML_set_int_subset(nNode->doc, nNode);
                }
                if ( nNode->_private != NULL ) {
                    PmmFixOwner( PmmPROXYNODE(nNode),
                                 PmmOWNERPO(PmmPROXYNODE(self)) );
                }
            }
      }
    OUTPUT:
        RETVAL

SV*
replaceNode( self,nNode )
        xmlNodePtr self
        xmlNodePtr nNode
    PREINIT:
        xmlNodePtr ret = NULL;
        ProxyNodePtr owner = NULL;
    CODE:
        if ( domIsParent( self, nNode ) == 1 ) {
            XSRETURN_UNDEF;
        }
        owner = PmmOWNERPO(PmmPROXYNODE(self));

        if ( self->type != XML_ATTRIBUTE_NODE ) {
              ret = domReplaceChild( self->parent, nNode, self);
        }
        else {
             ret = xmlReplaceNode( self, nNode );
        }
        if ( ret ) {
            LibXML_reparent_removed_node(ret);
            RETVAL = PmmNodeToSv(ret, PmmOWNERPO(PmmPROXYNODE(ret)));
            if (nNode->type == XML_DTD_NODE) {
                LibXML_set_int_subset(nNode->doc, nNode);
            }
            if ( nNode->_private != NULL ) {
                PmmFixOwner(PmmPROXYNODE(nNode), owner);
            }
        }
        else {
            croak( "replacement failed" );
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
removeChild( self, node )
        xmlNodePtr self
        xmlNodePtr node
    PREINIT:
        xmlNodePtr ret;
    CODE:
        ret = domRemoveChild( self, node );
        if (ret == NULL) {
            XSRETURN_UNDEF;
        }
        else {
            LibXML_reparent_removed_node(ret);
            RETVAL = PmmNodeToSv(ret, NULL);
        }
    OUTPUT:
        RETVAL

void
removeChildNodes( self )
        xmlNodePtr self
    PREINIT:
        xmlNodePtr elem, fragment;
        ProxyNodePtr docfrag;
    CODE:
        docfrag  = PmmNewFragment( self->doc );
        fragment = PmmNODE( docfrag );
        elem = self->children;
        while ( elem ) {
            xmlNodePtr next = elem->next;
            xmlUnlinkNode( elem );
            if (elem->type == XML_ATTRIBUTE_NODE
                || elem->type == XML_DTD_NODE) {
                if (PmmPROXYNODE(elem) == NULL) {
                    xmlFreeNode(elem);
                }
            }
            else {
                /* this following piece is the function of domAppendChild()
                 * but in this special case we can avoid most of the logic of
                 * that function.
                 */
                if ( fragment->children != NULL ) {
                    xs_warn("unlink node!\n");
                    domAddNodeToList( elem, fragment->last, NULL );
                }
                else {
                    fragment->children = elem;
                    fragment->last     = elem;
                    elem->parent= fragment;
                }
                PmmFixOwnerNode( elem, docfrag );
            }
            elem = next;
        }

        self->children = self->last = NULL;
        if ( PmmREFCNT(docfrag) <= 0 ) {
            xs_warn( "have not references left" );
            PmmREFCNT_inc( docfrag );
            PmmREFCNT_dec( docfrag );
        }

void
unbindNode( self )
        xmlNodePtr self
    ALIAS:
        XML::LibXML::Node::unlink = 1
        XML::LibXML::Node::unlinkNode = 2
    PREINIT:
        ProxyNodePtr docfrag     = NULL;
    CODE:
        PERL_UNUSED_VAR(ix);
        if ( self->type != XML_DOCUMENT_NODE
             && self->type != XML_DOCUMENT_FRAG_NODE ) {
            xmlUnlinkNode( self );
            LibXML_reparent_removed_node(self);
        }

SV*
appendChild( self, nNode )
        xmlNodePtr self
        xmlNodePtr nNode
    PREINIT:
        xmlNodePtr rNode;
    CODE:
        if (self->type == XML_DOCUMENT_NODE ) {
            /* NOT_SUPPORTED_ERR
             */
            switch ( nNode->type ) {
            case XML_ELEMENT_NODE:
                warn("Appending an element to a document node not supported yet!");
                XSRETURN_UNDEF;
                break;
            case XML_DOCUMENT_FRAG_NODE:
                warn("Appending a document fragment node to a document node not supported yet!");
                XSRETURN_UNDEF;
                break;
            case XML_TEXT_NODE:
            case XML_CDATA_SECTION_NODE:
                warn("Appending text node not supported on a document node yet!");
                XSRETURN_UNDEF;
                break;
            default:
                break;
            }
        }

        rNode = domAppendChild( self, nNode );

        if ( rNode == NULL ) {
            XSRETURN_UNDEF;
        }

        RETVAL = PmmNodeToSv( nNode,
                              PmmOWNERPO(PmmPROXYNODE(self)) );
        if (nNode->type == XML_DTD_NODE) {
            LibXML_set_int_subset(self->doc, nNode);
        }
        PmmFixOwner( SvPROXYNODE(RETVAL), PmmPROXYNODE(self) );
    OUTPUT:
        RETVAL

SV*
addChild( self, nNode )
        xmlNodePtr self
        xmlNodePtr nNode
    PREINIT:
        xmlNodePtr retval = NULL;
        ProxyNodePtr proxy;
    CODE:
        switch ( nNode->type ) {
        case XML_DOCUMENT_FRAG_NODE:
            croak("Adding document fragments with addChild not supported!");
            XSRETURN_UNDEF;
        case XML_DOCUMENT_NODE :
        case XML_HTML_DOCUMENT_NODE :
        case XML_DOCB_DOCUMENT_NODE :
            croak("addChild: HIERARCHY_REQUEST_ERR\n");
            XSRETURN_UNDEF;
        case XML_NOTATION_NODE :
        case XML_NAMESPACE_DECL :
        case XML_DTD_NODE :
        case XML_DOCUMENT_TYPE_NODE :
        case XML_ENTITY_DECL :
        case XML_ELEMENT_DECL :
        case XML_ATTRIBUTE_DECL :
            croak("addChild: unsupported node type!");
            XSRETURN_UNDEF;
	default:
	  break;
        }

        xmlUnlinkNode(nNode);
        proxy = PmmPROXYNODE(nNode);
        retval = xmlAddChild( self, nNode );

        if ( retval == NULL ) {
            croak( "Error: addChild failed (check node types)!\n" );
        }

        if ( retval != nNode ) {
            xs_warn( "node was lost during operation\n" );
            PmmNODE(proxy) = NULL;
        }

        RETVAL = PmmNodeToSv( retval,
                              PmmOWNERPO(PmmPROXYNODE(self)) );
        if ( retval != self ) {
            PmmFixOwner( SvPROXYNODE(RETVAL), PmmPROXYNODE(self) );
        }
    OUTPUT:
        RETVAL


SV*
addSibling( self, nNode )
        xmlNodePtr self
        xmlNodePtr nNode
    PREINIT:
        xmlNodePtr ret = NULL;
        ProxyNodePtr owner = NULL;
    CODE:
        if ( nNode->type == XML_DOCUMENT_FRAG_NODE ) {
            croak("Adding document fragments with addSibling not yet supported!");
            XSRETURN_UNDEF;
        }
        owner = PmmOWNERPO(PmmPROXYNODE(self));

        if (self->type == XML_TEXT_NODE && nNode->type == XML_TEXT_NODE
            && self->name == nNode->name) {
            /* As a result of text merging, the added node may be freed. */
            xmlNodePtr copy = xmlCopyNode(nNode, 0);
            ret = xmlAddSibling(self, copy);

            if (ret) {
                RETVAL = PmmNodeToSv(ret, owner);
                /* Unlink original node. */
                xmlUnlinkNode(nNode);
                LibXML_reparent_removed_node(nNode);
            }
            else {
                xmlFreeNode(copy);
                XSRETURN_UNDEF;
            }
        }
        else {
            ret = xmlAddSibling( self, nNode );

            if ( ret ) {
                RETVAL = PmmNodeToSv(ret, owner);
                if (nNode->type == XML_DTD_NODE) {
                    LibXML_set_int_subset(self->doc, nNode);
                }
                PmmFixOwner(SvPROXYNODE(RETVAL), owner);
            }
            else {
                XSRETURN_UNDEF;
            }
        }
    OUTPUT:
        RETVAL

SV*
cloneNode( self, deep=0 )
        xmlNodePtr self
        int deep
    PREINIT:
        xmlNodePtr ret;
        xmlDocPtr doc = NULL;
        ProxyNodePtr docfrag = NULL;
    CODE:
        ret = PmmCloneNode( self, deep );
        if ( ret == NULL ) {
            XSRETURN_UNDEF;
        }

        if ( ret->type  == XML_DTD_NODE ) {
            RETVAL = PmmNodeToSv(ret, NULL);
        }
        else {
            doc = self->doc;

            if ( doc != NULL ) {
                xmlSetTreeDoc(ret, doc); /* setting to self, no need to clear psvi */
            }

            docfrag = PmmNewFragment( doc );
            xmlAddChild( PmmNODE(docfrag), ret );
            RETVAL = PmmNodeToSv(ret, docfrag);
        }
    OUTPUT:
        RETVAL

int
isSameNode( self, oNode )
        xmlNodePtr self
        xmlNodePtr oNode
    ALIAS:
        XML::LibXML::Node::isEqual = 1
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = ( self == oNode ) ? 1 : 0;
    OUTPUT:
        RETVAL

IV
unique_key( self )
        xmlNodePtr self
    CODE:
        /* Cast pointer to IV */
        RETVAL = PTR2IV(self);
    OUTPUT:
        RETVAL

SV *
baseURI( self )
        xmlNodePtr self
    PREINIT:
        xmlChar * uri;
    CODE:
        uri = xmlNodeGetBase( self->doc, self );
        RETVAL = C2Sv( uri, NULL );
        xmlFree( uri );
    OUTPUT:
        RETVAL

void
setBaseURI( self, URI )
        xmlNodePtr self
        SV * URI
    PREINIT:
        xmlChar * uri;
    CODE:
        uri = nodeSv2C( URI, self );
        if ( uri != NULL ) {
            xmlNodeSetBase( self, uri );
        }

SV*
toString( self, format=0, useDomEncoding = &PL_sv_undef )
        xmlNodePtr self
        SV * useDomEncoding
        int format
    ALIAS:
        XML::LibXML::Node::serialize = 1
    PREINIT:
        xmlBufferPtr buffer;
        const xmlChar *ret = NULL;
        SV* internalFlag = NULL;
        int oldTagFlag = xmlSaveNoEmptyTags;
    CODE:
        PERL_UNUSED_VAR(ix);
        internalFlag = get_sv("XML::LibXML::setTagCompression", 0);

        if ( internalFlag ) {
            xmlSaveNoEmptyTags = SvTRUE(internalFlag);
        }
        buffer = xmlBufferCreate();

        if ( format <= 0 ) {
            xmlNodeDump( buffer,
                         self->doc,
                         self, 0, format);
        }
        else {
            int t_indent_var = xmlIndentTreeOutput;
            xmlIndentTreeOutput = 1;
            xmlNodeDump( buffer,
                         self->doc,
                         self, 0, format);
            xmlIndentTreeOutput = t_indent_var;
        }

        ret = xmlBufferContent( buffer );

        xmlSaveNoEmptyTags = oldTagFlag;

        if ( ret != NULL ) {
            if ( useDomEncoding != &PL_sv_undef && SvTRUE(useDomEncoding) ) {
                RETVAL = nodeC2Sv((xmlChar*)ret, PmmNODE(PmmPROXYNODE(self))) ;
                SvUTF8_off(RETVAL);
            }
            else {
                RETVAL = C2Sv((xmlChar*)ret, NULL) ;
            }
            xmlBufferFree( buffer );
        }
        else {
            xmlBufferFree( buffer );
            xs_warn("Failed to convert node to string");
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL


SV *
_toStringC14N(self, comments=0, xpath=&PL_sv_undef, exclusive=0, inc_prefix_list=NULL, xpath_context)
        xmlNodePtr self
        int comments
        SV * xpath
        int exclusive
        char** inc_prefix_list
        SV * xpath_context

    PREINIT:
        xmlChar *result               = NULL;
        xmlChar *nodepath             = NULL;
        xmlXPathContextPtr child_ctxt = NULL;
        xmlXPathObjectPtr xpath_res = NULL;
        xmlNodeSetPtr nodelist        = NULL;
        xmlNodePtr refNode            = NULL;
        PREINIT_SAVED_ERROR
    INIT:
        /* due to how c14n is implemented, the nodeset it receives must
          include child nodes; ie, child nodes aren't assumed to be rendered.
          so we use an xpath expression to find all of the child nodes. */

        if ( self->doc == NULL ) {
            croak("Node passed to toStringC14N must be part of a document");
        }

        refNode = self;
    CODE:
        if ( xpath != NULL && xpath != &PL_sv_undef ) {
            nodepath = Sv2C( xpath, NULL );
        }

        if ( nodepath != NULL && xmlStrlen( nodepath ) == 0 ) {
            xmlFree( nodepath );
            nodepath = NULL;
        }

        if ( nodepath == NULL
             && self->type != XML_DOCUMENT_NODE
             && self->type != XML_HTML_DOCUMENT_NODE
             && self->type != XML_DOCB_DOCUMENT_NODE
           ) {
            if (comments)
	      nodepath = xmlStrdup( (const xmlChar *) "(. | .//node() | .//@* | .//namespace::*)" );
            else
              nodepath = xmlStrdup( (const xmlChar *) "(. | .//node() | .//@* | .//namespace::*)[not(self::comment())]" );
        }

        if ( nodepath != NULL ) {
            if ( self->type == XML_DOCUMENT_NODE
                 || self->type == XML_HTML_DOCUMENT_NODE
                 || self->type == XML_DOCB_DOCUMENT_NODE ) {
                refNode = xmlDocGetRootElement( self->doc );
            }
	    if (SvOK(xpath_context)) {
	      child_ctxt = INT2PTR(xmlXPathContextPtr,SvIV(SvRV(xpath_context)));
	      if ( child_ctxt == NULL ) {
		croak("XPathContext: missing xpath context\n");
	      }
	    } else {
	      xpath_context = NULL;
	      child_ctxt = xmlXPathNewContext(self->doc);
	    }
            if (!child_ctxt) {
                if ( nodepath != NULL ) {
                    xmlFree( nodepath );
                }
                croak("Failed to create xpath context");
            }

            child_ctxt->node = self;
	    LibXML_configure_namespaces(child_ctxt);

            xpath_res = xmlXPathEval(nodepath, child_ctxt);
	    if (child_ctxt->namespaces != NULL) {
	      xmlFree( child_ctxt->namespaces );
	      child_ctxt->namespaces = NULL;
	    }
	    if (!xpath_context) xmlXPathFreeContext(child_ctxt);
	    if ( nodepath != NULL ) {
	      xmlFree( nodepath );
	    }

            if (xpath_res == NULL) {
                croak("2 Failed to compile xpath expression");
            }

            nodelist = xpath_res->nodesetval;
            if ( nodelist == NULL ) {
                xmlXPathFreeObject(xpath_res);
                croak( "cannot canonize empty nodeset!" );
            }
        }

        INIT_ERROR_HANDLER;

        xmlC14NDocDumpMemory( self->doc,
                              nodelist,
                              exclusive, (xmlChar **) inc_prefix_list,
                              comments,
                              &result );

        if ( xpath_res ) xmlXPathFreeObject(xpath_res);
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(0);

        if (result == NULL) {
             croak("Failed to convert doc to string in doc->toStringC14N");
        } else {
            RETVAL = C2Sv( result, NULL );
            xmlFree(result);
        }
    OUTPUT:
        RETVAL

SV*
string_value ( self, useDomEncoding = &PL_sv_undef )
        xmlNodePtr self
        SV * useDomEncoding
    ALIAS:
        to_literal = 1
        textContent = 2
    PREINIT:
         xmlChar * string = NULL;
    CODE:
        PERL_UNUSED_VAR(ix);
        /* we can't just return a string, because of UTF8! */
        string = xmlXPathCastNodeToString(self);
        if ( SvTRUE(useDomEncoding) ) {
            RETVAL = nodeC2Sv(string,
                              self);
        }
        else {
            RETVAL = C2Sv(string,
                          NULL);
        }
        xmlFree(string);
    OUTPUT:
        RETVAL

double
to_number ( self )
        xmlNodePtr self
    CODE:
        RETVAL = xmlXPathCastNodeToNumber(self);
    OUTPUT:
        RETVAL


void
_find( pnode, pxpath, to_bool )
        SV* pnode
        SV * pxpath
	int to_bool
    PREINIT:
        xmlNodePtr node = PmmSvNode(pnode);
        ProxyNodePtr owner = NULL;
        xmlXPathObjectPtr found = NULL;
        xmlNodeSetPtr nodelist = NULL;
        xmlChar * xpath = NULL;
        xmlXPathCompExprPtr comp = NULL;
        PREINIT_SAVED_ERROR
    INIT:
        if ( node == NULL ) {
            croak( "lost node" );
        }
        if (sv_isobject(pxpath) && sv_isa(pxpath,"XML::LibXML::XPathExpression")) {
             comp = INT2PTR(xmlXPathCompExprPtr,SvIV((SV*)SvRV( pxpath )));
             if (!comp) XSRETURN_UNDEF;
        } else {
            xpath = nodeSv2C(pxpath, node);
            if ( !(xpath && xmlStrlen(xpath)) ) {
                xs_warn( "bad xpath\n" );
                if ( xpath )
                    xmlFree(xpath);
                croak( "empty XPath found" );
                XSRETURN_UNDEF;
            }
        }
    PPCODE:
        INIT_ERROR_HANDLER;
        if (comp) {
          found = domXPathCompFind( node, comp, to_bool );
        } else {
          found = domXPathFind( node, xpath, to_bool );
          xmlFree( xpath );
        }
        CLEANUP_ERROR_HANDLER;
        if (found) {
	    REPORT_ERROR(1);
            switch (found->type) {
                case XPATH_NODESET:
                    /* return as a NodeList */
                    /* access ->nodesetval */
                    XPUSHs(sv_2mortal(newSVpv("XML::LibXML::NodeList", 0)));
                    nodelist = found->nodesetval;
                    if ( nodelist ) {
                        if ( nodelist->nodeNr > 0 ) {
                            int i;
                            const char * cls = "XML::LibXML::Node";
                            xmlNodePtr tnode;
                            SV * element;
                            int l = nodelist->nodeNr;

                            owner = PmmOWNERPO(SvPROXYNODE(pnode));
                            for( i=0 ; i < l; i++){
                                /* we have to create a new instance of an
                                 * objectptr. and then
                                 * place the current node into the new
                                 * object. afterwards we can
                                 * push the object to the array!
                                 */
                                tnode = nodelist->nodeTab[i];

                                /* let's be paranoid */
                                if (tnode->type == XML_NAMESPACE_DECL) {
                                     xmlNsPtr newns = xmlCopyNamespace((xmlNsPtr)tnode);
                                    if ( newns != NULL ) {
                                        element = NEWSV(0,0);
                                        cls = PmmNodeTypeName( tnode );
                                        element = sv_setref_pv( element,
                                                                (const char *)cls,
                                                                (void*)newns
                                                          );
                                    }
                                    else {
                                        continue;
                                    }
                                }
                                else {
                                    element = PmmNodeToSv(tnode, owner);
                                }

                                XPUSHs( sv_2mortal(element) );
                            }
                        }
                        xmlXPathFreeNodeSet( found->nodesetval );
                        found->nodesetval = NULL;
                    }
                    break;
                case XPATH_BOOLEAN:
                    /* return as a Boolean */
                    /* access ->boolval */
                    XPUSHs(sv_2mortal(newSVpv("XML::LibXML::Boolean", 0)));
                    XPUSHs(sv_2mortal(newSViv(found->boolval)));
                    break;
                case XPATH_NUMBER:
                    /* return as a Number */
                    /* access ->floatval */
                    XPUSHs(sv_2mortal(newSVpv("XML::LibXML::Number", 0)));
                    XPUSHs(sv_2mortal(newSVnv(found->floatval)));
                    break;
                case XPATH_STRING:
                    /* access ->stringval */
                    /* return as a Literal */
                    XPUSHs(sv_2mortal(newSVpv("XML::LibXML::Literal", 0)));
                    XPUSHs(sv_2mortal(C2Sv(found->stringval, NULL)));
                    break;
                default:
                    croak("Unknown XPath return type");
            }
            xmlXPathFreeObject(found);
        } else {
	  REPORT_ERROR(0);
	}

void
_findnodes( pnode, perl_xpath )
        SV* pnode
        SV * perl_xpath
    PREINIT:
        xmlNodePtr node = PmmSvNode(pnode);
        ProxyNodePtr owner = NULL;
        xmlNodeSetPtr nodelist = NULL;
        SV * element = NULL ;
        xmlChar * xpath = NULL ;
        xmlXPathCompExprPtr comp = NULL;
        PREINIT_SAVED_ERROR
    INIT:
        if ( node == NULL ) {
	  if ( xpath )
	    xmlFree(xpath);
	  croak( "lost node" );
        }
        if (sv_isobject(perl_xpath) && sv_isa(perl_xpath,"XML::LibXML::XPathExpression")) {
             comp = INT2PTR(xmlXPathCompExprPtr,SvIV((SV*)SvRV( perl_xpath )));
             if (!comp) XSRETURN_UNDEF;
        } else {
            xpath = nodeSv2C(perl_xpath, node);
            if ( !(xpath && xmlStrlen(xpath)) ) {
                xs_warn( "bad xpath\n" );
                if ( xpath )
                    xmlFree(xpath);
                croak( "empty XPath found" );
                XSRETURN_UNDEF;
            }
        }
    PPCODE:
        INIT_ERROR_HANDLER;
        if (comp) {
	    nodelist = domXPathCompSelect( node, comp );
        } else {
	    nodelist = domXPathSelect( node, xpath );
            xmlFree(xpath);
        }
        CLEANUP_ERROR_HANDLER;

        if ( nodelist ) {
	    REPORT_ERROR(1);
            if ( nodelist->nodeNr > 0 ) {
                int i;
                int len = nodelist->nodeNr;
                const char * cls = "XML::LibXML::Node";
                xmlNodePtr tnode;
                owner = PmmOWNERPO(SvPROXYNODE(pnode));

                for(i=0 ; i < len; i++){
                    /* we have to create a new instance of an objectptr.
                     * and then place the current node into the new object.
                     * afterwards we can push the object to the array!
                     */
                    element = NULL;
                    tnode = nodelist->nodeTab[i];
                    if (tnode->type == XML_NAMESPACE_DECL) {
                        xmlNsPtr newns = xmlCopyNamespace((xmlNsPtr)tnode);
                        if ( newns != NULL ) {
                            element = NEWSV(0,0);
                            cls = PmmNodeTypeName( tnode );
                            element = sv_setref_pv( element,
                                                    (const char *)cls,
                                                    newns
                                                  );
                        }
                        else {
                            continue;
                        }
                    }
                    else {
                        element = PmmNodeToSv(tnode, owner);
                    }

                    XPUSHs( sv_2mortal(element) );
                }
            }
            xmlXPathFreeNodeSet( nodelist );
        } else {
	  REPORT_ERROR(0);
	}

void
getNamespaces( pnode )
        SV * pnode
    ALIAS:
        namespaces = 1
    PREINIT:
        xmlNodePtr node;
        xmlNsPtr ns = NULL;
        xmlNsPtr newns = NULL;
        SV* element = &PL_sv_undef;
        const char * class = "XML::LibXML::Namespace";
    INIT:
        PERL_UNUSED_VAR(ix);
        node = PmmSvNode(pnode);
        if ( node == NULL ) {
            croak( "lost node" );
        }
    PPCODE:
        if (node->type == XML_ELEMENT_NODE) {
	  ns = node->nsDef;
	  while ( ns != NULL ) {
	    if (ns->prefix != NULL || ns->href != NULL) {
	      newns = xmlCopyNamespace(ns);
	      if ( newns != NULL ) {
		element = NEWSV(0,0);
		element = sv_setref_pv( element,
					(const char *)class,
					(void*)newns
					);
		XPUSHs( sv_2mortal(element) );
	      }
	    }
            ns = ns->next;
	  }
	}

SV *
getNamespace( node )
        xmlNodePtr node
    ALIAS:
        localNamespace = 1
        localNS        = 2
    PREINIT:
        xmlNsPtr ns = NULL;
        xmlNsPtr newns = NULL;
        const char * class = "XML::LibXML::Namespace";
    CODE:
        PERL_UNUSED_VAR(ix);
	if ( node->type == XML_ELEMENT_NODE
	    || node->type == XML_ATTRIBUTE_NODE
	    || node->type == XML_PI_NODE ) {
	  ns = node->ns;
	  if ( ns != NULL ) {
            newns = xmlCopyNamespace(ns);
            if ( newns != NULL ) {
	      RETVAL = NEWSV(0,0);
	      RETVAL = sv_setref_pv( RETVAL,
				     (const char *)class,
				     (void*)newns
				     );
            } else {
	      XSRETURN_UNDEF;
	    }
	  }
	  else {
            XSRETURN_UNDEF;
	  }
	} else {
          XSRETURN_UNDEF;
	}
    OUTPUT:
        RETVAL


SV *
nodePath( self )
        xmlNodePtr self
    PREINIT:
        xmlChar * path = NULL;
    CODE:
        path = xmlGetNodePath( self );
        if ( path == NULL ) {
            croak( "cannot calculate path for the given node" );
        }
        RETVAL = C2Sv( path, NULL );
        xmlFree(path);
    OUTPUT:
        RETVAL

int
line_number( self )
        xmlNodePtr self
    CODE:
        RETVAL = xmlGetLineNo( self );
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Element

SV*
new(CLASS, name )
        char * name
    PREINIT:
        xmlNodePtr newNode;
        ProxyNodePtr docfrag = NULL;
    CODE:
        docfrag = PmmNewFragment(NULL);
        newNode = xmlNewNode( NULL, (const xmlChar*)name );
        newNode->doc = NULL;
        xmlAddChild(PmmNODE(docfrag), newNode);
        RETVAL = PmmNodeToSv(newNode, docfrag );
    OUTPUT:
        RETVAL

int
_setNamespace(self, namespaceURI, namespacePrefix = &PL_sv_undef, flag = 1 )
        SV * self
        SV * namespaceURI
        SV * namespacePrefix
        int flag
    PREINIT:
        xmlNodePtr node = PmmSvNode(self);
        xmlChar * nsURI = nodeSv2C(namespaceURI,node);
        xmlChar * nsPrefix = NULL;
        xmlNsPtr ns = NULL;
    INIT:
        if ( node == NULL ) {
            croak( "lost node" );
        }
    CODE:
       /* if ( !nsURI ){
            XSRETURN_UNDEF;
		} */

        nsPrefix = nodeSv2C(namespacePrefix, node);
        if ( xmlStrlen( nsPrefix ) == 0 ) {
            xmlFree(nsPrefix);
            nsPrefix = NULL;
        }
        if ( xmlStrlen( nsURI ) == 0 ) {
            xmlFree(nsURI);
            nsURI = NULL;
        }
        if ( nsPrefix == NULL && nsURI == NULL ) {
	    /* special case: empty namespace */
	    if ( (ns = xmlSearchNs(node->doc, node, NULL)) &&
		 ( ns->href && xmlStrlen( ns->href ) != 0 ) ) {
		/* won't take it */
		RETVAL = 0;
	    } else if ( flag ) {
		/* no namespace */
		xmlSetNs(node, NULL);
		RETVAL = 1;
	    } else {
		RETVAL = 0;
	    }
	}
        else if ( flag && (ns = xmlSearchNs(node->doc, node, nsPrefix)) ) {
	  /* user just wants to set the namespace for the node */
	  /* try to reuse an existing declaration for the prefix */
            if ( xmlStrEqual( ns->href, nsURI ) ) {
                RETVAL = 1;
            }
            else if ( (ns = xmlNewNs( node, nsURI, nsPrefix )) ) {
                RETVAL = 1;
            }
            else {
                RETVAL = 0;
            }
        }
        else if ( (ns = xmlNewNs( node, nsURI, nsPrefix )) )
	  RETVAL = 1;
	else
	  RETVAL = 0;

        if ( flag && ns ) {
            xmlSetNs(node, ns);
        }
        if ( nsPrefix ) xmlFree(nsPrefix);
        if ( nsURI ) xmlFree(nsURI);
    OUTPUT:
        RETVAL

int
setNamespaceDeclURI( self, svprefix, newURI )
        xmlNodePtr self
        SV * svprefix
        SV * newURI
    PREINIT:
        xmlChar * prefix = NULL;
        xmlChar * nsURI = NULL;
        xmlNsPtr ns;
    CODE:
	RETVAL = 0;
	prefix = nodeSv2C( svprefix , self );
	nsURI = nodeSv2C( newURI , self );
	/* null empty values */
	if ( prefix && xmlStrlen(prefix) == 0) {
	  xmlFree( prefix );
	  prefix = NULL;
	}
        if ( nsURI && xmlStrlen(nsURI) == 0) {
	  xmlFree( nsURI );
	  nsURI = NULL;
	}
        ns = self->nsDef;
        while ( ns ) {
	  if ((ns->prefix || ns->href ) &&
	      ( xmlStrcmp( ns->prefix, prefix ) == 0 )) {
	    if (ns->href) xmlFree((char*)ns->href);
	    ns->href = nsURI;
	    if ( nsURI == NULL ) {
	      domRemoveNsRefs( self, ns );
	    } else
	      nsURI = NULL; /* do not free it */
	    RETVAL = 1;
	    break;
	    } else {
	    ns = ns->next;
	  }
	}
        if ( prefix ) xmlFree( prefix );
        if ( nsURI ) xmlFree( nsURI );
    OUTPUT:
        RETVAL

int
setNamespaceDeclPrefix( self, svprefix, newPrefix )
        xmlNodePtr self
        SV * svprefix
        SV * newPrefix
    PREINIT:
        xmlChar * prefix = NULL;
        xmlChar * nsPrefix = NULL;
        xmlNsPtr ns;
    CODE:
	RETVAL = 0;
	prefix = nodeSv2C( svprefix , self );
	nsPrefix = nodeSv2C( newPrefix , self );
	/* null empty values */
	if ( prefix != NULL && xmlStrlen(prefix) == 0) {
	  xmlFree( prefix );
	  prefix = NULL;
	}
        if ( nsPrefix != NULL && xmlStrlen(nsPrefix) == 0) {
	  xmlFree( nsPrefix );
	  nsPrefix = NULL;
	}
        if ( xmlStrcmp( prefix, nsPrefix ) == 0 ) {
	  RETVAL = 1;
	} else {
	  /* check that new prefix is not in scope */
	  ns = xmlSearchNs( self->doc, self, nsPrefix );
	  if ( ns != NULL ) {
	    if (nsPrefix != NULL) xmlFree( nsPrefix );
	    if (prefix != NULL) xmlFree( prefix );
	    croak("setNamespaceDeclPrefix: prefix '%s' is in use", ns->prefix);
	  }
	  /* lookup the declaration */
	  ns = self->nsDef;
	  while ( ns != NULL ) {
	    if ((ns->prefix != NULL || ns->href != NULL) &&
		xmlStrcmp( ns->prefix, prefix ) == 0 ) {
	      if ( ns->href == NULL && nsPrefix != NULL ) {
		/* xmlns:foo="" - no go */
		if ( prefix != NULL) xmlFree(prefix);
		croak("setNamespaceDeclPrefix: cannot set non-empty prefix for empty namespace");
	      }
	      if ( ns->prefix != NULL )
		xmlFree( (xmlChar*)ns->prefix );
	      ns->prefix = nsPrefix;
	      nsPrefix = NULL; /* do not free it */
	      RETVAL = 1;
	      break;
	    } else {
	      ns = ns->next;
	    }
	  }
	}
        if ( nsPrefix != NULL ) xmlFree(nsPrefix);
        if ( prefix != NULL) xmlFree(prefix);
    OUTPUT:
        RETVAL


SV*
_getNamespaceDeclURI( self, ns_prefix )
        xmlNodePtr self
        SV * ns_prefix
    PREINIT:
        xmlChar * prefix;
        xmlNsPtr ns;
    CODE:
        prefix = nodeSv2C(ns_prefix, self );
        if ( prefix != NULL && xmlStrlen(prefix) == 0) {
		xmlFree( prefix );
		prefix = NULL;
	  }
        RETVAL = &PL_sv_undef;
        ns = self->nsDef;
        while ( ns != NULL ) {
		if ( (ns->prefix != NULL || ns->href != NULL) &&
		     xmlStrcmp( ns->prefix, prefix ) == 0 ) {
		    RETVAL = C2Sv(ns->href, NULL);
		    break;
		} else {
		    ns = ns->next;
		}
	  }
        if ( prefix != NULL ) {
		xmlFree( prefix );
	  }

    OUTPUT:
        RETVAL

int
hasAttribute( self, attr_name )
        xmlNodePtr self
        SV * attr_name
    PREINIT:
        xmlChar * name;
    CODE:
        name  = nodeSv2C(attr_name, self );
        if ( ! name ) {
            XSRETURN_UNDEF;
        }
        if ( domGetAttrNode( self, name ) ) {
            RETVAL = 1;
        }
        else {
            RETVAL = 0;
        }
        xmlFree(name);
    OUTPUT:
        RETVAL

int
hasAttributeNS( self, namespaceURI, attr_name )
        xmlNodePtr self
        SV * namespaceURI
        SV * attr_name
    PREINIT:
        xmlChar * name;
        xmlChar * nsURI;
	xmlNodePtr attr;
    CODE:
        name = nodeSv2C(attr_name, self );
        nsURI = nodeSv2C(namespaceURI, self );

        if ( name == NULL ) {
            if ( nsURI != NULL ) {
              xmlFree(nsURI);
            }
            XSRETURN_UNDEF;
        }
        if ( nsURI != NULL && xmlStrlen(nsURI) == 0 ){
            xmlFree(nsURI);
            nsURI = NULL;
        }
        attr = (xmlNodePtr) xmlHasNsProp( self, name, nsURI );
        if ( attr && attr->type == XML_ATTRIBUTE_NODE ) {
            RETVAL = 1;
        }
        else {
            RETVAL = 0;
        }

        xmlFree(name);
        if ( nsURI != NULL ){
            xmlFree(nsURI);
        }
    OUTPUT:
        RETVAL

SV*
_getAttribute( self, attr_name, useDomEncoding = 0 )
        xmlNodePtr self
        SV * attr_name
        int useDomEncoding
    PREINIT:
        xmlChar * name;
        xmlChar * prefix    = NULL;
        xmlChar * localname = NULL;
        xmlChar * ret = NULL;
        xmlNsPtr ns = NULL;
    CODE:
        name = nodeSv2C(attr_name, self );
        if( !name ) {
            XSRETURN_UNDEF;
        }

        ret = xmlGetNoNsProp(self, name);
        if ( ret == NULL ) {
            localname = xmlSplitQName2(name, &prefix);
            if ( localname != NULL ) {
		    ns = xmlSearchNs( self->doc, self, prefix );
		    if ( ns != NULL ) {
			  ret = xmlGetNsProp(self, localname, ns->href);
		    }
		    if ( prefix != NULL) {
			  xmlFree( prefix );
		    }
		    xmlFree( localname );
		}
        }
        xmlFree(name);
        if ( ret ) {
            if ( useDomEncoding ) {
                RETVAL = nodeC2Sv(ret, self);
            }
            else {
                RETVAL = C2Sv(ret, NULL);
            }
            xmlFree( ret );
        }
        else {
            XSRETURN_UNDEF;
	}

    OUTPUT:
        RETVAL

void
_setAttribute( self, attr_name, attr_value )
        xmlNodePtr self
        SV * attr_name
        SV * attr_value
    PREINIT:
        xmlChar * name  = NULL;
        xmlChar * value = NULL;
#if LIBXML_VERSION < 20621
        xmlChar * prefix    = NULL;
        xmlChar * localname = NULL;
#endif
    CODE:
        name  = nodeSv2C(attr_name, self );

        if ( !LibXML_test_node_name(name) ) {
            xmlFree(name);
            croak( "bad name" );
        }
        value = nodeSv2C(attr_value, self );
#if LIBXML_VERSION >= 20621
	/*
	 * For libxml2-2.6.21 and later we can use just xmlSetProp
         */
        xmlSetProp(self,name,value);
#else
        /*
         * but xmlSetProp does not work correctly for older libxml2 versions
	 * The following is copied from libxml2 source
         * with xmlSplitQName3 replaced by xmlSplitQName2 for compatibility
         * with older libxml2 versions
         */
        localname = xmlSplitQName2(name, &prefix);
        if (localname != NULL) {
          xmlNsPtr ns;
	  ns = xmlSearchNs(self->doc, self, prefix);
	  if (prefix != NULL)
	      xmlFree(prefix);
	  if (ns != NULL)
	      xmlSetNsProp(self, ns, localname, value);
	  else
              xmlSetNsProp(self, NULL, name, value);
          xmlFree(localname);
        } else {
            xmlSetNsProp(self, NULL, name, value);
        }
#endif
        xmlFree(name);
        xmlFree(value);


void
removeAttribute( self, attr_name )
        xmlNodePtr self
        SV * attr_name
    PREINIT:
        xmlChar * name;
        xmlAttrPtr xattr = NULL;
    CODE:
        name  = nodeSv2C(attr_name, self );
        if ( name ) {
            xattr = domGetAttrNode( self, name );

            if ( xattr ) {
                xmlUnlinkNode((xmlNodePtr)xattr);
                if ( xattr->_private ) {
                    PmmFixOwner((ProxyNodePtr)xattr->_private, NULL);
                }
                else {
                    xmlFreeProp(xattr);
                }
            }
            xmlFree(name);
        }

SV*
getAttributeNode( self, attr_name )
        xmlNodePtr self
        SV * attr_name
    PREINIT:
        xmlChar * name;
        xmlAttrPtr ret = NULL;
    CODE:
        name = nodeSv2C(attr_name, self );
        if ( !name ) {
            XSRETURN_UNDEF;
        }

        ret = domGetAttrNode( self, name );
        xmlFree(name);
        if ( ret ) {
            RETVAL = PmmNodeToSv( (xmlNodePtr)ret,
                                   PmmOWNERPO(PmmPROXYNODE(self)) );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV *
setAttributeNode( self, attr_node )
        xmlNodePtr self
        SV * attr_node
    PREINIT:
        xmlAttrPtr attr = (xmlAttrPtr)PmmSvNode( attr_node );
        xmlAttrPtr ret = NULL;
    INIT:
        if ( attr == NULL ) {
            croak( "lost attribute" );
        }
    CODE:
        if ( attr != NULL && attr->type != XML_ATTRIBUTE_NODE ) {
            XSRETURN_UNDEF;
        }
        if ( attr->doc != self->doc ) {
	    domImportNode( self->doc, (xmlNodePtr)attr, 1, 1);
        }
        ret = domGetAttrNode( self, attr->name );
        if ( ret != NULL ) {
            if ( ret != attr ) {
                xmlReplaceNode( (xmlNodePtr)ret, (xmlNodePtr)attr );
            }
            else {
                XSRETURN_UNDEF;
            }
        }
        else {
            xmlAddChild( self, (xmlNodePtr)attr );
        }

        if ( attr->_private != NULL ) {
            PmmFixOwner( SvPROXYNODE(attr_node), PmmPROXYNODE(self) );
        }

        if ( ret == NULL ) {
            XSRETURN_UNDEF;
        }

        RETVAL = PmmNodeToSv( (xmlNodePtr)ret, NULL );
        PmmFixOwner( SvPROXYNODE(RETVAL), NULL );
    OUTPUT:
        RETVAL

SV *
_getAttributeNS( self, namespaceURI, attr_name, useDomEncoding = 0 )
        xmlNodePtr self
        SV * namespaceURI
        SV * attr_name
        int useDomEncoding
    PREINIT:
        xmlChar * name;
        xmlChar * nsURI;
        xmlChar * ret = NULL;
    CODE:
        name = nodeSv2C( attr_name, self );
        nsURI = nodeSv2C( namespaceURI, self );
        if ( !name ) {
            xmlFree(nsURI);
            XSRETURN_UNDEF;
        }
        if ( nsURI && xmlStrlen(nsURI) ) {
            ret = xmlGetNsProp( self, name, nsURI );
        }
        else {
            ret = xmlGetProp( self, name );
        }

        xmlFree( name );
        if ( nsURI ) {
            xmlFree( nsURI );
        }
        if ( ret ) {
            if (useDomEncoding) {
                RETVAL = nodeC2Sv( ret, self );
            } else {
                RETVAL = C2Sv( ret, NULL );
            }
            xmlFree( ret );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

void
_setAttributeNS( self, namespaceURI, attr_name, attr_value )
        xmlNodePtr self
        SV * namespaceURI
        SV * attr_name
        SV * attr_value
    PREINIT:
        xmlChar * nsURI;
        xmlChar * name  = NULL;
        xmlChar * value = NULL;
        xmlNsPtr ns         = NULL;
        xmlChar * localname = NULL;
        xmlChar * prefix    = NULL;
        xmlNsPtr * all_ns   = NULL;
        int i;
    INIT:
        name  = nodeSv2C( attr_name, self );

        if ( !LibXML_test_node_name(name) ) {
            xmlFree(name);
            croak( "bad name" );
        }

        nsURI = nodeSv2C( namespaceURI, self );
        localname = xmlSplitQName2(name, &prefix);
        if ( localname ) {
            xmlFree( name );
            name = localname;
        }
    CODE:
        value = nodeSv2C( attr_value, self );

        if ( nsURI && xmlStrlen(nsURI) ) {
            xs_warn( "found uri" );

            ns = xmlSearchNsByHref( self->doc, self, nsURI );

            /*
             * check for any prefixed namespaces occluded by a default namespace
             * because xmlSearchNsByHref will return default namespaces unless
             * you are searching on an attribute node, which may not exist yet
             */
            if ( ns && !ns->prefix )
            {
                all_ns = xmlGetNsList(self->doc, self);
                if ( all_ns )
                {
                    i = 0;
                    ns = all_ns[i];
                    while ( ns )
                    {
                        if ( ns->prefix && xmlStrEqual(ns->href, nsURI) )
                        {
                            break;
                        }
                        ns = all_ns[i++];
                    }
                    xmlFree(all_ns);
                }
            }

            if ( !ns ) {
                /* create new ns */
                if ( prefix && xmlStrlen( prefix ) ) {
                    ns = xmlNewNs(self, nsURI , prefix);
                }
                else {
                    ns = NULL;
                }
            }
        }

        if ( nsURI && xmlStrlen(nsURI) && !ns ) {
	  if ( prefix ) xmlFree( prefix );
	  if ( nsURI ) xmlFree( nsURI );
	  xmlFree( name );
	  xmlFree( value );
	  croak( "bad ns attribute!" );
        }
        else {
            /* warn( "set attribute %s->%s", name, value ); */
            xmlSetNsProp( self, ns, name, value );
        }

        if ( prefix ) {
            xmlFree( prefix );
        }
        if ( nsURI ) {
            xmlFree( nsURI );
        }
        xmlFree( name );
        xmlFree( value );

void
removeAttributeNS( self, namespaceURI, attr_name )
        xmlNodePtr self
        SV * namespaceURI
        SV * attr_name
    PREINIT:
        xmlChar * nsURI;
        xmlChar * name  = NULL;
        xmlAttrPtr xattr = NULL;
    CODE:
        nsURI = nodeSv2C( namespaceURI, self );
        name  = nodeSv2C( attr_name, self );
        if ( ! name ) {
            xmlFree(nsURI);
            XSRETURN_UNDEF;
        }

        if ( nsURI && xmlStrlen(nsURI) ) {
            xattr = xmlHasNsProp( self, name, nsURI );
        }
        else {
            xattr = xmlHasNsProp( self, name, NULL );
        }
        if ( xattr && xattr->type == XML_ATTRIBUTE_NODE ) {
            xmlUnlinkNode((xmlNodePtr)xattr);
            if ( xattr->_private ) {
                PmmFixOwner((ProxyNodePtr)xattr->_private, NULL);
            }
            else {
                xmlFreeProp(xattr);
            }
        }
        xmlFree(nsURI);
        xmlFree( name );


SV*
getAttributeNodeNS( self,namespaceURI, attr_name )
        xmlNodePtr self
        SV * namespaceURI
        SV * attr_name
    PREINIT:
        xmlChar * nsURI;
        xmlChar * name;
        xmlAttrPtr ret = NULL;
    CODE:
        nsURI = nodeSv2C(namespaceURI, self );
        name = nodeSv2C(attr_name, self );
        if ( !name ) {
            xmlFree(nsURI);
            XSRETURN_UNDEF;
        }
        if ( nsURI && xmlStrlen(nsURI) ) {
            ret = xmlHasNsProp( self, name, nsURI );
        }
        else {
            ret = xmlHasNsProp( self, name, NULL );
        }
        xmlFree(name);
        if ( nsURI ) {
            xmlFree(nsURI);
        }
        if ( ret &&
	     ret->type == XML_ATTRIBUTE_NODE /* we don't want fixed attribute decls */
	   ) {
            RETVAL = PmmNodeToSv( (xmlNodePtr)ret,
                                   PmmOWNERPO(PmmPROXYNODE(self)) );
        }
        else {
            /* warn("no prop\n"); */
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV *
setAttributeNodeNS( self, attr_node )
        xmlNodePtr self
        SV * attr_node
    PREINIT:
        xmlAttrPtr attr = (xmlAttrPtr)PmmSvNode( attr_node );
        xmlNsPtr ns = NULL;
        xmlAttrPtr ret = NULL;
    INIT:
        if ( attr == NULL ) {
            croak( "lost attribute node" );
        }
    CODE:
        if ( attr->type != XML_ATTRIBUTE_NODE ) {
            XSRETURN_UNDEF;
        }

        if ( attr->doc != self->doc ) {
           domImportNode( self->doc, (xmlNodePtr)attr, 1,1);
        }


        ns = attr->ns;
        if ( ns != NULL ) {
            ret = xmlHasNsProp( self, ns->href, attr->name );
        }
        else {
            ret = xmlHasNsProp( self, NULL, attr->name );
        }

        if ( ret && ret->type == XML_ATTRIBUTE_NODE ) {
            if ( ret != attr ) {
                xmlReplaceNode( (xmlNodePtr)ret, (xmlNodePtr)attr );
            }
            else {
                XSRETURN_UNDEF;
            }
        }
        else {
            xmlAddChild( self, (xmlNodePtr)attr );
            xmlReconciliateNs(self->doc, self);
        }
        if ( attr->_private != NULL ) {
            PmmFixOwner( SvPROXYNODE(attr_node), PmmPROXYNODE(self) );
        }
        if ( ret != NULL && ret->type == XML_ATTRIBUTE_NODE ) {
	    RETVAL = PmmNodeToSv( (xmlNodePtr)ret, NULL );
	    PmmFixOwner( SvPROXYNODE(RETVAL), NULL );
	} else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV *
removeAttributeNode( self, attr_node )
        xmlNodePtr self
        SV * attr_node
    PREINIT:
        xmlAttrPtr attr = (xmlAttrPtr)PmmSvNode( attr_node );
        xmlAttrPtr ret;
    INIT:
        if ( attr == NULL ) {
            croak( "lost attribute node" );
        }
    CODE:
        if ( attr->type != XML_ATTRIBUTE_NODE ) {
            XSRETURN_UNDEF;
        }
        if ( attr->parent != self ) {
            XSRETURN_UNDEF;
        }
        ret = attr;
        xmlUnlinkNode( (xmlNodePtr)attr );
        RETVAL = PmmNodeToSv( (xmlNodePtr)ret, NULL );
        PmmFixOwner( SvPROXYNODE(RETVAL), NULL );
    OUTPUT:
        RETVAL

void
appendText( self, string )
        xmlNodePtr self
        SV * string
    ALIAS:
        appendTextNode = 1
        XML::LibXML::DocumentFragment::appendText = 2
        XML::LibXML::DocumentFragment::appendTextNode = 3
    PREINIT:
        xmlChar * content = NULL;
    INIT:
        PERL_UNUSED_VAR(ix);
        content = nodeSv2C( string, self );
        if ( content == NULL ) {
            XSRETURN_UNDEF;
        }
        if ( xmlStrlen(content) == 0 ) {
            xmlFree( content );
            XSRETURN_UNDEF;
        }
    CODE:
        xmlNodeAddContent( self, content );
        xmlFree(content);


void
appendTextChild( self, strname, strcontent=&PL_sv_undef, nsURI=&PL_sv_undef )
        xmlNodePtr self
        SV * strname
        SV * strcontent
        SV * nsURI
    PREINIT:
        xmlChar * name;
        xmlChar * content = NULL;
        xmlChar * encstr  = NULL;
    INIT:
        name    = nodeSv2C( strname, self );
        if ( xmlStrlen(name) == 0 ) {
            xmlFree(name);
            XSRETURN_UNDEF;
        }
    CODE:
        content = nodeSv2C(strcontent, self);
        if ( content &&  xmlStrlen( content ) == 0 ) {
            xmlFree(content);
            content=NULL;
        }
        else if ( content ) {
            encstr = xmlEncodeEntitiesReentrant( self->doc, content );
            xmlFree(content);
        }

        xmlNewChild( self, NULL, name, encstr );

        if ( encstr )
            xmlFree(encstr);
        xmlFree(name);

SV *
addNewChild( self, namespaceURI, nodename )
        xmlNodePtr self
        SV * namespaceURI
        SV * nodename
    ALIAS:
        XML::LibXML::DocumentFragment::addNewChild = 1
    PREINIT:
        xmlChar * nsURI = NULL;
        xmlChar * name  = NULL;
        xmlChar * localname  = NULL;
        xmlChar * prefix     = NULL;
        xmlNodePtr newNode = NULL;
        xmlNodePtr prev = NULL;
        xmlNsPtr ns = NULL;
    CODE:
        PERL_UNUSED_VAR(ix);
        name = nodeSv2C(nodename, self);
        if ( name &&  xmlStrlen( name ) == 0 ) {
            xmlFree(name);
            XSRETURN_UNDEF;
        }

        nsURI = nodeSv2C(namespaceURI, self);
        if ( nsURI &&  xmlStrlen( nsURI ) == 0 ) {
            xmlFree(nsURI);
            nsURI=NULL;
        }

        if ( nsURI != NULL ) {
            localname = xmlSplitQName2(name, &prefix);
            ns = xmlSearchNsByHref(self->doc, self, nsURI);

            newNode = xmlNewDocNode(self->doc,
                                ns,
                                localname?localname:name,
                                NULL);
            if ( ns == NULL )  {
	        xmlSetNs(newNode,xmlNewNs(newNode, nsURI, prefix));
            }

            xmlFree(localname);
            xmlFree(prefix);
            xmlFree(nsURI);
        }
        else {
            newNode = xmlNewDocNode(self->doc,
                                    NULL,
                                    name,
                                    NULL);
        }
        xmlFree(name);
        /* add the node to the parent node */
        newNode->type = XML_ELEMENT_NODE;
        newNode->parent = self;
        newNode->doc = self->doc;

        if (self->children == NULL) {
            self->children = newNode;
            self->last = newNode;
        } else {
            prev = self->last;
            prev->next = newNode;
            newNode->prev = prev;
            self->last = newNode;
        }
        RETVAL = PmmNodeToSv(newNode, PmmOWNERPO(PmmPROXYNODE(self)) );
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Text

SV *
new( CLASS, content )
        SV * content
    PREINIT:
        xmlChar * data;
        xmlNodePtr newNode;
        ProxyNodePtr docfrag = NULL;
    CODE:
        data = Sv2C(content, NULL);
        newNode = xmlNewText( data );
        xmlFree(data);
        if( newNode != NULL ) {
            docfrag = PmmNewFragment( NULL );
            xmlAddChild(PmmNODE(docfrag), newNode);
            RETVAL = PmmNodeToSv(newNode,docfrag);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV *
substringData( self, offset, length )
        xmlNodePtr self
        int offset
        int length
    PREINIT:
        xmlChar * data = NULL;
        xmlChar * substr = NULL;
    CODE:
        if ( offset >= 0 && length >= 0 ) {
            data = domGetNodeValue( self );
            if ( data != NULL ) {
                substr = xmlUTF8Strsub( data, offset, length );
                RETVAL = C2Sv( (const xmlChar*)substr, NULL );
                xmlFree( substr );
            }
            else {
                XSRETURN_UNDEF;
            }
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

void
setData( self, value )
        xmlNodePtr self
        SV * value
    ALIAS:
        XML::LibXML::Attr::setValue = 1
        XML::LibXML::PI::_setData = 2
    PREINIT:
        xmlChar * encstr = NULL;
    CODE:
        PERL_UNUSED_VAR(ix);
        encstr = nodeSv2C(value,self);
        domSetNodeValue( self, encstr );
        xmlFree(encstr);

void
appendData( self, value )
        xmlNodePtr self
        SV * value
    PREINIT:
        xmlChar * encstring = NULL;
        int strlen = 0;
    CODE:
        encstring = Sv2C( value,
                          self->doc!=NULL ? self->doc->encoding : NULL );

       if ( encstring != NULL ) {
            strlen = xmlStrlen( encstring );
            xmlTextConcat( self, encstring, strlen );
            xmlFree( encstring );
        }

void
insertData( self, offset, value )
        xmlNodePtr self
        int offset
        SV * value
    PREINIT:
        xmlChar * after= NULL;
        xmlChar * data = NULL;
        xmlChar * new  = NULL;
        xmlChar * encstring = NULL;
        int dl = 0;
    CODE:
        if ( offset >= 0 ) {
            encstring = Sv2C( value,
                              self->doc!=NULL ? self->doc->encoding : NULL );
            if ( encstring != NULL && xmlStrlen( encstring ) > 0 ) {
                data = domGetNodeValue(self);
                if ( data != NULL && xmlStrlen( data ) > 0 ) {
                    if ( xmlUTF8Strlen( data ) < offset ) {
                        data = xmlStrcat( data, encstring );
                        domSetNodeValue( self, data );
                    }
                    else {
                        dl = xmlUTF8Strlen( data ) - offset;

                        if ( offset > 0 )
                            new   = xmlUTF8Strsub(data, 0, offset );

                        after = xmlUTF8Strsub(data, offset, dl );

                        if ( new != NULL ) {
                            new = xmlStrcat(new, encstring );
                        }
                        else {
                            new = xmlStrdup( encstring );
                        }

                        if ( after != NULL )
                            new = xmlStrcat(new, after );

                        domSetNodeValue( self, new );

                        xmlFree( new );
                        xmlFree( after );
                    }
                    xmlFree( data );
                }
                else {
                    domSetNodeValue( self, encstring );
                }
                xmlFree(encstring);
            }
        }

void
deleteData( self, offset, length )
        xmlNodePtr self
        int offset
        int length
    PREINIT:
        xmlChar * data  = NULL;
        xmlChar * after = NULL;
        xmlChar * new   = NULL;
        int len = 0;
        int dl1 = 0;
        int dl2 = 0;
    CODE:
        if ( length > 0 && offset >= 0 ) {
            data = domGetNodeValue(self);
            len = xmlUTF8Strlen( data );
            if ( data != NULL
                 && len > 0
                 && len > offset ) {
                dl1 = offset + length;
                if ( offset > 0 )
                    new = xmlUTF8Strsub( data, 0, offset );

                if ( len > dl1 ) {
                    dl2 = len - dl1;
                    after = xmlUTF8Strsub( data, dl1, dl2 );
                    if ( new != NULL ) {
                        new = xmlStrcat( new, after );
                        xmlFree(after);
                    }
                    else {
                        new = after;
                    }
                }

                domSetNodeValue( self, new );
                xmlFree(new);
            }
        }

void
replaceData( self, offset,length, value )
        xmlNodePtr self
        int offset
        int length
        SV * value
    PREINIT:
        xmlChar * after= NULL;
        xmlChar * data = NULL;
        xmlChar * new  = NULL;
        xmlChar * encstring = NULL;
        int len = 0;
        int dl1 = 0;
        int dl2 = 0;
    CODE:
        if ( offset >= 0 ) {
            encstring = Sv2C( value,
                              self->doc!=NULL ? self->doc->encoding : NULL );

            if ( encstring != NULL && xmlStrlen( encstring ) > 0 ) {
                data = domGetNodeValue(self);
                len = xmlUTF8Strlen( data );

                if ( data != NULL
                     && len > 0
                     && len > offset  ) {

                    dl1 = offset + length;
                    if ( dl1 < len ) {
                        dl2 = xmlUTF8Strlen( data ) - dl1;
                        if ( offset > 0 ) {
                            new = xmlUTF8Strsub(data, 0, offset );
                            new = xmlStrcat(new, encstring );
                        }
                        else {
                            new   = xmlStrdup( encstring );
                        }

                        after = xmlUTF8Strsub(data, dl1, dl2 );
                        new = xmlStrcat(new, after );

                        domSetNodeValue( self, new );

                        xmlFree( new );
                        xmlFree( after );
                    }
                    else {
                        /* replace until end! */
                        if ( offset > 0 ) {
                            new = xmlUTF8Strsub(data, 0, offset );
                            new = xmlStrcat(new, encstring );
                        }
                        else {
                            new   = xmlStrdup( encstring );
                        }
                        domSetNodeValue( self, new );
                        xmlFree( new );
                    }
                    xmlFree( data );
                }

                xmlFree(encstring);
            }
        }

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Comment

SV *
new( CLASS, content )
        SV * content
    PREINIT:
        xmlChar * encstring;
        xmlNodePtr newNode;
        ProxyNodePtr docfrag = NULL;
    CODE:
        encstring = Sv2C(content, NULL);
        newNode = xmlNewComment( encstring );
        xmlFree(encstring);
        if( newNode != NULL ) {
            docfrag = PmmNewFragment( NULL );
            xmlAddChild(PmmNODE(docfrag), newNode);
            RETVAL = PmmNodeToSv(newNode,docfrag);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::CDATASection

SV *
new( CLASS , content )
        SV * content
    PREINIT:
        xmlChar * encstring;
        xmlNodePtr newNode;
        ProxyNodePtr docfrag = NULL;
    CODE:
        encstring = Sv2C(content, NULL);
        newNode = xmlNewCDataBlock( NULL , encstring, xmlStrlen( encstring ) );
        xmlFree(encstring);
        if ( newNode != NULL ){
            docfrag = PmmNewFragment( NULL );
            xmlAddChild(PmmNODE(docfrag), newNode);
            RETVAL = PmmNodeToSv(newNode,docfrag);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::DocumentFragment

SV*
new( CLASS )
    PREINIT:
        xmlNodePtr real_doc=NULL;
    CODE:
        real_doc = xmlNewDocFragment( NULL );
        RETVAL = PmmNodeToSv( real_doc, NULL );
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Attr

SV*
new( CLASS, pname, pvalue )
        SV * pname
        SV * pvalue
    PREINIT:
        xmlNodePtr attr = NULL;
        xmlChar * name;
        xmlChar * value;
    CODE:
        name  = Sv2C(pname,NULL);
        value = Sv2C(pvalue,NULL);
        if ( name == NULL ) {
            XSRETURN_UNDEF;
        }
        attr =  (xmlNodePtr)xmlNewProp( NULL, name, value );
        attr->doc = NULL;
        RETVAL = PmmNodeToSv(attr,NULL);
    OUTPUT:
        RETVAL


SV*
parentElement( self )
    ALIAS:
        XML::LibXML::Attr::getParentNode = 1
        XML::LibXML::Attr::getNextSibling = 2
        XML::LibXML::Attr::getPreviousSibling = 3
        XML::LibXML::Attr::nextSibling = 4
        XML::LibXML::Attr::previousSibling = 5
    CODE:
        /* override the original parentElement(), since this an attribute is
         * not part of the main tree
         */

        PERL_UNUSED_VAR(ix);
        XSRETURN_UNDEF;
    OUTPUT:
        RETVAL

SV*
serializeContent( self, useDomEncoding = &PL_sv_undef )
        SV * self
        SV * useDomEncoding
    PREINIT:
        xmlBufferPtr buffer;
        const xmlChar *ret = NULL;
        xmlAttrPtr node = (xmlAttrPtr)PmmSvNode(self);
    CODE:
        buffer = xmlBufferCreate();
        domAttrSerializeContent(buffer, node);
        if ( xmlBufferLength(buffer) > 0 ) {
            ret = xmlBufferContent( buffer );
        }
        if ( ret != NULL ) {
            if ( useDomEncoding != &PL_sv_undef && SvTRUE(useDomEncoding) ) {
                RETVAL = nodeC2Sv((xmlChar*)ret, PmmNODE(PmmPROXYNODE(node))) ;
            }
            else {
                RETVAL = C2Sv((xmlChar*)ret, NULL) ;
            }
            xmlBufferFree( buffer );
        }
        else {
            xmlBufferFree( buffer );
            xs_warn("Failed to convert attribute to string");
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
toString(self , format=0, useDomEncoding = &PL_sv_undef )
	SV * self
        SV * useDomEncoding
	int format
    ALIAS:
        XML::LibXML::Attr::serialize = 1
    PREINIT:
        xmlAttrPtr node = (xmlAttrPtr)PmmSvNode(self);
        xmlBufferPtr buffer;
        const xmlChar *ret = NULL;
    CODE:
        /* we add an extra method for serializing attributes since
           XML::LibXML::Node::toString causes segmentation fault inside
           libxml2
	 */
        PERL_UNUSED_VAR(ix);
        buffer = xmlBufferCreate();
        xmlBufferAdd(buffer, BAD_CAST " ", 1);
        if ((node->ns != NULL) && (node->ns->prefix != NULL)) {
	  xmlBufferAdd(buffer, node->ns->prefix, xmlStrlen(node->ns->prefix));
	  xmlBufferAdd(buffer, BAD_CAST ":", 1);
	}
        xmlBufferAdd(buffer, node->name, xmlStrlen(node->name));
        xmlBufferAdd(buffer, BAD_CAST "=\"", 2);
        domAttrSerializeContent(buffer, node);
        xmlBufferAdd(buffer, BAD_CAST "\"", 1);

        if ( xmlBufferLength(buffer) > 0 ) {
            ret = xmlBufferContent( buffer );
        }
        if ( ret != NULL ) {
            if ( useDomEncoding != &PL_sv_undef && SvTRUE(useDomEncoding) ) {
                RETVAL = nodeC2Sv((xmlChar*)ret, PmmNODE(PmmPROXYNODE(node))) ;
            }
            else {
                RETVAL = C2Sv((xmlChar*)ret, NULL) ;
            }
            xmlBufferFree( buffer );
        }
        else {
            xmlBufferFree( buffer );
            xs_warn("Failed to convert attribute to string");
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL


int
_setNamespace(self, namespaceURI, namespacePrefix = &PL_sv_undef )
        SV * self
        SV * namespaceURI
        SV * namespacePrefix
    PREINIT:
        xmlAttrPtr node = (xmlAttrPtr)PmmSvNode(self);
        xmlChar * nsURI = nodeSv2C(namespaceURI,(xmlNodePtr)node);
        xmlChar * nsPrefix = NULL;
        xmlNsPtr ns = NULL;
    INIT:
        if ( node == NULL ) {
            croak( "lost node" );
        }
    CODE:
        if ( !nsURI || xmlStrlen(nsURI)==0 ){
	    xmlSetNs((xmlNodePtr)node, NULL);
            RETVAL = 1;
        }
        if ( !node->parent ) {
            XSRETURN_UNDEF;
        }
        nsPrefix = nodeSv2C(namespacePrefix, (xmlNodePtr)node);
        if ( (ns = xmlSearchNs(node->doc, node->parent, nsPrefix)) &&
             xmlStrEqual( ns->href, nsURI) ) {
	    /* same uri and prefix */
	    RETVAL = 1;
	}
	else if ( (ns = xmlSearchNsByHref(node->doc, node->parent, nsURI)) ) {
	    /* set uri, but with a different prefix */
            RETVAL = 1;
	}
        else if (! RETVAL)
            RETVAL = 0;

        if ( ns ) {
	    if ( ns->prefix ) {
		xmlSetNs((xmlNodePtr)node, ns);
	    } else {
                RETVAL = 0;
	    }
	}
        xmlFree(nsPrefix);
        xmlFree(nsURI);
    OUTPUT:
        RETVAL

int
isId( self )
        SV * self
    PREINIT:
        xmlAttrPtr attr = (xmlAttrPtr)PmmSvNode(self);
	xmlNodePtr elem;
    CODE:
        if ( attr == NULL ) {
          XSRETURN_UNDEF;
        }
	elem = attr->parent;
	if ( elem == NULL || elem->doc == NULL ) {
	  XSRETURN_UNDEF;
        }
        RETVAL = xmlIsID( elem->doc, elem, attr );
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Namespace

SV*
new(CLASS, namespaceURI, namespacePrefix=&PL_sv_undef)
        const char * CLASS
        SV * namespaceURI
        SV * namespacePrefix
    PREINIT:
        xmlNsPtr ns = NULL;
        xmlChar* nsURI;
        xmlChar* nsPrefix;
    CODE:
        RETVAL = &PL_sv_undef;

        nsURI = Sv2C(namespaceURI,NULL);
        if ( !nsURI ) {
            XSRETURN_UNDEF;
        }
        nsPrefix = Sv2C(namespacePrefix, NULL);
        ns = xmlNewNs(NULL, nsURI, nsPrefix);
        if ( ns ) {
            RETVAL = NEWSV(0,0);
            RETVAL = sv_setref_pv( RETVAL,
                                   CLASS,
                                   (void*)ns);
	}
        xmlFree(nsURI);
        if ( nsPrefix )
            xmlFree(nsPrefix);
    OUTPUT:
        RETVAL

void
DESTROY(self)
        SV * self
    PREINIT:
        xmlNsPtr ns = INT2PTR(xmlNsPtr,SvIV(SvRV(self)));
    CODE:
        xs_warn( "DESTROY NS" );
        if (ns) {
            xmlFreeNs(ns);
        }

int
nodeType(self)
        SV * self
    ALIAS:
        getType = 1
    PREINIT:
        xmlNsPtr ns = INT2PTR(xmlNsPtr,SvIV(SvRV(self)));
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = ns->type;
    OUTPUT:
        RETVAL

SV*
declaredURI(self)
        SV * self
    ALIAS:
        value = 1
        nodeValue = 2
        getData = 3
        getValue = 4
        value2 = 5
	href = 6
    PREINIT:
        xmlNsPtr ns = INT2PTR(xmlNsPtr,SvIV(SvRV(self)));
        xmlChar * href;
    CODE:
        PERL_UNUSED_VAR(ix);
        href = xmlStrdup(ns->href);
        RETVAL = C2Sv(href, NULL);
        xmlFree(href);
    OUTPUT:
        RETVAL

SV*
declaredPrefix(self)
        SV * self
    ALIAS:
	localname = 1
        getLocalName = 2
    PREINIT:
        xmlNsPtr ns = INT2PTR(xmlNsPtr,SvIV(SvRV(self)));
        xmlChar * prefix;
    CODE:
        PERL_UNUSED_VAR(ix);
        prefix = xmlStrdup(ns->prefix);
        RETVAL = C2Sv(prefix, NULL);
        xmlFree(prefix);
    OUTPUT:
        RETVAL

SV*
unique_key( self )
        SV * self
    PREINIT:
        xmlNsPtr ns = INT2PTR(xmlNsPtr,SvIV(SvRV(self)));
        xmlChar* key;
    CODE:
        /* Concatenate prefix and URI with vertical bar dividing*/
        key = xmlStrdup(ns->prefix);
        key = xmlStrcat(key, (const xmlChar*)"|");
        key = xmlStrcat(key, ns->href);
        RETVAL = C2Sv(key, NULL);
    OUTPUT:
        RETVAL

int
_isEqual(self, ref_node)
       SV * self
       SV * ref_node
    PREINIT:
       xmlNsPtr ns = INT2PTR(xmlNsPtr,SvIV(SvRV(self)));
       xmlNsPtr ons = INT2PTR(xmlNsPtr,SvIV(SvRV(ref_node)));
    CODE:
       RETVAL = 0;
       if ( ns == ons ) {
           RETVAL = 1;
       }
       else if ( xmlStrEqual(ns->href, ons->href)
            && xmlStrEqual(ns->prefix, ons->prefix) ) {
           RETVAL = 1;
       }
    OUTPUT:
       RETVAL


MODULE = XML::LibXML         PACKAGE = XML::LibXML::Dtd

SV *
new(CLASS, external, system)
        char * external
        char * system
    ALIAS:
        parse_uri = 1
    PREINIT:
        xmlDtdPtr dtd = NULL;
        PREINIT_SAVED_ERROR
    CODE:
        PERL_UNUSED_VAR(ix);
        INIT_ERROR_HANDLER;
        dtd = xmlParseDTD((const xmlChar*)external, (const xmlChar*)system);
        if ( dtd == NULL ) {
	    CLEANUP_ERROR_HANDLER;
            REPORT_ERROR(0);
            XSRETURN_UNDEF;
        } else {
            xmlSetTreeDoc((xmlNodePtr)dtd, NULL);
            RETVAL = PmmNodeToSv( (xmlNodePtr) dtd, NULL );
	    CLEANUP_ERROR_HANDLER;
            REPORT_ERROR(0);
        }
    OUTPUT:
        RETVAL

SV*
systemId( self )
        xmlDtdPtr self
    ALIAS:
        getSystemId = 1
    CODE:
        PERL_UNUSED_VAR(ix);
	if ( self->SystemID == NULL ) {
            XSRETURN_UNDEF;
	} else {
            RETVAL = C2Sv(self->SystemID,NULL);
	}
    OUTPUT:
        RETVAL

SV*
publicId( self )
        xmlDtdPtr self
    ALIAS:
        getPublicId = 1
    CODE:
        PERL_UNUSED_VAR(ix);
	if ( self->ExternalID == NULL ) {
            XSRETURN_UNDEF;
	} else {
            RETVAL = C2Sv(self->ExternalID,NULL);
	}
    OUTPUT:
        RETVAL

SV *
parse_string(CLASS, str, ...)
        char * str
    PREINIT:
        xmlDtdPtr res;
        SV * encoding_sv;
        xmlParserInputBufferPtr buffer;
        xmlCharEncoding enc = XML_CHAR_ENCODING_NONE;
        xmlChar * new_string;
        PREINIT_SAVED_ERROR
    CODE:
        INIT_ERROR_HANDLER;
        if (items > 2) {
            encoding_sv = ST(2);
            if (items > 3) {
	        CLEANUP_ERROR_HANDLER;
                croak("parse_string: too many parameters");
            }
            /* warn("getting encoding...\n"); */
            enc = xmlParseCharEncoding(SvPV_nolen(encoding_sv));
            if (enc == XML_CHAR_ENCODING_ERROR) {
	        CLEANUP_ERROR_HANDLER;
                REPORT_ERROR(1);
                croak("Parse of encoding %s failed", SvPV_nolen(encoding_sv));
            }
        }
        buffer = xmlAllocParserInputBuffer(enc);
        /* buffer = xmlParserInputBufferCreateMem(str, xmlStrlen(str), enc); */
        if ( !buffer) {
	    CLEANUP_ERROR_HANDLER;
            REPORT_ERROR(1);
            croak("cannot create buffer!\n" );
	}
        new_string = xmlStrdup((const xmlChar*)str);
        xmlParserInputBufferPush(buffer, xmlStrlen(new_string), (const char*)new_string);

        res = xmlIOParseDTD(NULL, buffer, enc);

        /* NOTE: xmlIOParseDTD is documented to free its InputBuffer */
        xmlFree(new_string);
        if ( res && LibXML_will_die_ctx(saved_error, 0) )
	    xmlFreeDtd( res );
	CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(0);
        if (res == NULL) {
            croak("no DTD parsed!");
        }
        RETVAL = PmmNodeToSv((xmlNodePtr)res, NULL);
    OUTPUT:
        RETVAL


#ifdef HAVE_SCHEMAS

MODULE = XML::LibXML         PACKAGE = XML::LibXML::RelaxNG

void
DESTROY( self )
        xmlRelaxNGPtr self
    CODE:
        xmlRelaxNGFree( self );


xmlRelaxNGPtr
parse_location( self, url )
        char * url
    PREINIT:
        const char * CLASS = "XML::LibXML::RelaxNG";
        xmlRelaxNGParserCtxtPtr rngctxt = NULL;
        PREINIT_SAVED_ERROR
    CODE:
        INIT_ERROR_HANDLER;

        rngctxt = xmlRelaxNGNewParserCtxt( url );
        if ( rngctxt == NULL ) {
            croak( "failed to initialize RelaxNG parser" );
        }
#ifndef WITH_SERRORS
        /* Register Error callbacks */
        xmlRelaxNGSetParserErrors( rngctxt,
                                  (xmlRelaxNGValidityErrorFunc)LibXML_error_handler_ctx,
                                  (xmlRelaxNGValidityWarningFunc)LibXML_error_handler_ctx,
                                  saved_error );
#endif
        RETVAL = xmlRelaxNGParse( rngctxt );
        xmlRelaxNGFreeParserCtxt( rngctxt );
	CLEANUP_ERROR_HANDLER;
        REPORT_ERROR((RETVAL == NULL) ? 0 : 1);
    OUTPUT:
        RETVAL


xmlRelaxNGPtr
parse_buffer( self, perlstring )
        SV * perlstring
    PREINIT:
        const char * CLASS = "XML::LibXML::RelaxNG";
        xmlRelaxNGParserCtxtPtr rngctxt = NULL;
        char * string = NULL;
        STRLEN len    = 0;
        PREINIT_SAVED_ERROR
    INIT:
        string = SvPV( perlstring, len );
        if ( string == NULL ) {
            croak( "cannot parse empty string" );
        }
    CODE:
        INIT_ERROR_HANDLER;

        rngctxt = xmlRelaxNGNewMemParserCtxt( string,len );
        if ( rngctxt == NULL ) {
            croak( "failed to initialize RelaxNG parser" );
        }
#ifndef WITH_SERRORS
        /* Register Error callbacks */
        xmlRelaxNGSetParserErrors( rngctxt,
                                  (xmlRelaxNGValidityErrorFunc)LibXML_error_handler_ctx,
                                  (xmlRelaxNGValidityWarningFunc)LibXML_error_handler_ctx,
                                  saved_error );
#endif
        RETVAL = xmlRelaxNGParse( rngctxt );
        xmlRelaxNGFreeParserCtxt( rngctxt );
	CLEANUP_ERROR_HANDLER;
        REPORT_ERROR((RETVAL == NULL) ? 0 : 1);
    OUTPUT:
        RETVAL


xmlRelaxNGPtr
parse_document( self, doc )
        xmlDocPtr doc
    PREINIT:
        const char * CLASS = "XML::LibXML::RelaxNG";
        xmlRelaxNGParserCtxtPtr rngctxt = NULL;
        PREINIT_SAVED_ERROR
    CODE:
        INIT_ERROR_HANDLER;

        rngctxt = xmlRelaxNGNewDocParserCtxt( doc );
        if ( rngctxt == NULL ) {
            croak( "failed to initialize RelaxNG parser" );
        }
#ifndef WITH_SERRORS
        /* Register Error callbacks */
        xmlRelaxNGSetParserErrors( rngctxt,
                                  (xmlRelaxNGValidityErrorFunc)  LibXML_error_handler_ctx,
                                  (xmlRelaxNGValidityWarningFunc)LibXML_error_handler_ctx,
                                  saved_error );
#endif
        RETVAL = xmlRelaxNGParse( rngctxt );
        xmlRelaxNGFreeParserCtxt( rngctxt );
	CLEANUP_ERROR_HANDLER;
        REPORT_ERROR((RETVAL == NULL) ? 0 : 1);
    OUTPUT:
        RETVAL

int
validate( self, doc )
        xmlRelaxNGPtr self
        xmlDocPtr doc
    PREINIT:
        xmlRelaxNGValidCtxtPtr vctxt = NULL;
        PREINIT_SAVED_ERROR
    CODE:
        INIT_ERROR_HANDLER;

        if (doc) {
            PmmClearPSVI(doc);
            PmmInvalidatePSVI(doc);
        }
        vctxt  = xmlRelaxNGNewValidCtxt( self );
        if ( vctxt == NULL ) {
            CLEANUP_ERROR_HANDLER;
            REPORT_ERROR(0);
            croak( "cannot initialize the validation context" );
        }
#ifndef WITH_SERRORS
        /* Register Error callbacks */
        xmlRelaxNGSetValidErrors( vctxt,
                                  (xmlRelaxNGValidityErrorFunc)LibXML_error_handler_ctx,
                                  (xmlRelaxNGValidityWarningFunc)LibXML_error_handler_ctx,
                                  saved_error );
#endif /* WITH_SERRORS */
	/* ** test only **
          xmlRelaxNGSetValidErrors( vctxt,
                                    (xmlRelaxNGValidityErrorFunc)fprintf,
                                    (xmlRelaxNGValidityWarningFunc)fprintf,
                                    stderr );
	*/
        RETVAL = xmlRelaxNGValidateDoc( vctxt, doc );
        xmlRelaxNGFreeValidCtxt( vctxt );
	CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(0);
        if ( RETVAL == 1 ) {
            XSRETURN_UNDEF;
        }
        if ( RETVAL == -1 ) {
            croak( "API Error" );
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL


MODULE = XML::LibXML         PACKAGE = XML::LibXML::Schema

void
DESTROY( self )
        xmlSchemaPtr self
    CODE:
        xmlSchemaFree( self );


xmlSchemaPtr
parse_location( self, url )
        char * url
    PREINIT:
        const char * CLASS = "XML::LibXML::Schema";
        xmlSchemaParserCtxtPtr rngctxt = NULL;
        PREINIT_SAVED_ERROR
    CODE:
        INIT_ERROR_HANDLER;

        rngctxt = xmlSchemaNewParserCtxt( url );
        if ( rngctxt == NULL ) {
	    CLEANUP_ERROR_HANDLER;
            REPORT_ERROR(0);
            croak( "failed to initialize Schema parser" );
        }

        /* Register Error callbacks */
        xmlSchemaSetParserErrors( rngctxt,
                                  (xmlSchemaValidityErrorFunc)LibXML_error_handler_ctx,
                                  (xmlSchemaValidityWarningFunc)LibXML_error_handler_ctx,
                                  saved_error );

        RETVAL = xmlSchemaParse( rngctxt );
        xmlSchemaFreeParserCtxt( rngctxt );
	CLEANUP_ERROR_HANDLER;
        REPORT_ERROR((RETVAL == NULL) ? 0 : 1);
    OUTPUT:
        RETVAL


xmlSchemaPtr
parse_buffer( self, perlstring )
        SV * perlstring
    PREINIT:
        const char * CLASS = "XML::LibXML::Schema";
        xmlSchemaParserCtxtPtr rngctxt = NULL;
        char * string = NULL;
        STRLEN len    = 0;
        PREINIT_SAVED_ERROR
    INIT:
        string = SvPV( perlstring, len );
        if ( string == NULL ) {
            croak( "cannot parse empty string" );
        }
    CODE:
        INIT_ERROR_HANDLER;

        rngctxt = xmlSchemaNewMemParserCtxt( string,len );
        if ( rngctxt == NULL ) {
	    CLEANUP_ERROR_HANDLER;
	    REPORT_ERROR(0);
            croak( "failed to initialize Schema parser" );
        }

        /* Register Error callbacks */
        xmlSchemaSetParserErrors( rngctxt,
                                  (xmlSchemaValidityErrorFunc)LibXML_error_handler_ctx,
                                  (xmlSchemaValidityWarningFunc)LibXML_error_handler_ctx,
                                  saved_error );

        RETVAL = xmlSchemaParse( rngctxt );
        xmlSchemaFreeParserCtxt( rngctxt );
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR((RETVAL == NULL) ? 0 : 1);
    OUTPUT:
        RETVAL


int
validate( self, node )
        xmlSchemaPtr self
        xmlNodePtr node
    PREINIT:
        xmlSchemaValidCtxtPtr vctxt = NULL;
        PREINIT_SAVED_ERROR
    CODE:
        INIT_ERROR_HANDLER;

        if (node->type == XML_DOCUMENT_NODE) {
            PmmClearPSVI((xmlDocPtr)node);
            PmmInvalidatePSVI((xmlDocPtr)node);
        }
        vctxt  = xmlSchemaNewValidCtxt( self );
        if ( vctxt == NULL ) {
            CLEANUP_ERROR_HANDLER;
	    REPORT_ERROR(0);
            croak( "cannot initialize the validation context" );
        }

        /* Register Error callbacks */
        xmlSchemaSetValidErrors( vctxt,
                                  (xmlSchemaValidityErrorFunc)LibXML_error_handler_ctx,
                                  (xmlSchemaValidityWarningFunc)LibXML_error_handler_ctx,
                                  saved_error );

        if (node->type == XML_DOCUMENT_NODE) {
            RETVAL = xmlSchemaValidateDoc(vctxt, (xmlDocPtr)node);
        }
        else {
            RETVAL = xmlSchemaValidateOneElement(vctxt, node);
        }

        xmlSchemaFreeValidCtxt( vctxt );

        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(0);
        if ( RETVAL > 0 ) {
            XSRETURN_UNDEF;
        }
        if ( RETVAL == -1 ) {
            croak( "API Error" );
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

#endif /* HAVE_SCHEMAS */

MODULE = XML::LibXML::XPathContext     PACKAGE = XML::LibXML::XPathContext

# PROTOTYPES: DISABLE

SV*
new( CLASS, ... )
        const char * CLASS
    PREINIT:
        SV * pnode = &PL_sv_undef;
    INIT:
        xmlXPathContextPtr ctxt;
    CODE:
        if( items > 1 )
            pnode = ST(1);

        ctxt = xmlXPathNewContext( NULL );
        ctxt->namespaces = NULL;

        New(0, ctxt->user, sizeof(XPathContextData), XPathContextData);
        if (ctxt->user == NULL) {
            croak("XPathContext: failed to allocate proxy object\n");
        }

        if (SvOK(pnode)) {
          XPathContextDATA(ctxt)->node = newSVsv(pnode);
        } else {
          XPathContextDATA(ctxt)->node = &PL_sv_undef;
        }

        XPathContextDATA(ctxt)->pool = NULL;
        XPathContextDATA(ctxt)->varLookup = NULL;
        XPathContextDATA(ctxt)->varData = NULL;

        xmlXPathRegisterFunc(ctxt,
                             (const xmlChar *) "document",
                             perlDocumentFunction);

        RETVAL = NEWSV(0,0),
        RETVAL = sv_setref_pv( RETVAL,
                               CLASS,
                               (void*)ctxt );
    OUTPUT:
        RETVAL

void
DESTROY( self )
        SV * self
    INIT:
        xmlXPathContextPtr ctxt = INT2PTR(xmlXPathContextPtr,SvIV(SvRV(self)));
    CODE:
        xs_warn( "DESTROY XPATH CONTEXT" );
        if (ctxt) {
            if (XPathContextDATA(ctxt) != NULL) {
                if (XPathContextDATA(ctxt)->node != NULL &&
                    SvOK(XPathContextDATA(ctxt)->node)) {
                    SvREFCNT_dec(XPathContextDATA(ctxt)->node);
                }
                if (XPathContextDATA(ctxt)->varLookup != NULL &&
                    SvOK(XPathContextDATA(ctxt)->varLookup)) {
                    SvREFCNT_dec(XPathContextDATA(ctxt)->varLookup);
                }
                if (XPathContextDATA(ctxt)->varData != NULL &&
                    SvOK(XPathContextDATA(ctxt)->varData)) {
                    SvREFCNT_dec(XPathContextDATA(ctxt)->varData);
                }
                if (XPathContextDATA(ctxt)->pool != NULL &&
                    SvOK(XPathContextDATA(ctxt)->pool)) {
                    SvREFCNT_dec((SV *)XPathContextDATA(ctxt)->pool);
                }
                Safefree(XPathContextDATA(ctxt));
            }

            if (ctxt->namespaces != NULL) {
                xmlFree( ctxt->namespaces );
            }
            if (ctxt->funcLookupData != NULL && SvROK((SV*)ctxt->funcLookupData)
                && SvTYPE(SvRV((SV *)ctxt->funcLookupData)) == SVt_PVHV) {
                SvREFCNT_dec((SV *)ctxt->funcLookupData);
            }

            xmlXPathFreeContext(ctxt);
        }

SV*
getContextNode( self )
        SV * self
    INIT:
        xmlXPathContextPtr ctxt = INT2PTR(xmlXPathContextPtr,SvIV(SvRV(self)));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context\n");
        }
    CODE:
        if(XPathContextDATA(ctxt)->node != NULL) {
            RETVAL = newSVsv(XPathContextDATA(ctxt)->node);
        } else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

int
getContextPosition( self )
        SV * self
    INIT:
        xmlXPathContextPtr ctxt = INT2PTR(xmlXPathContextPtr,SvIV(SvRV(self)));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context\n");
        }
    CODE:
        RETVAL = ctxt->proximityPosition;
    OUTPUT:
	RETVAL

int
getContextSize( self )
        SV * self
    INIT:
        xmlXPathContextPtr ctxt = INT2PTR(xmlXPathContextPtr,SvIV(SvRV(self)));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context\n");
        }
    CODE:
        RETVAL = ctxt->contextSize;
    OUTPUT:
	RETVAL

void
setContextNode( self , pnode )
        SV * self
        SV * pnode
    INIT:
        xmlXPathContextPtr ctxt = INT2PTR(xmlXPathContextPtr,SvIV(SvRV(self)));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context\n");
        }
    PPCODE:
        if (XPathContextDATA(ctxt)->node != NULL) {
            SvREFCNT_dec(XPathContextDATA(ctxt)->node);
        }
        if (SvOK(pnode)) {
            XPathContextDATA(ctxt)->node = newSVsv(pnode);
        } else {
            XPathContextDATA(ctxt)->node = NULL;
        }

void
setContextPosition( self , position )
        SV * self
        int position
    INIT:
        xmlXPathContextPtr ctxt = INT2PTR(xmlXPathContextPtr,SvIV(SvRV(self)));
        if ( ctxt == NULL )
            croak("XPathContext: missing xpath context\n");
        if ( position < -1 || position > ctxt->contextSize )
	    croak("XPathContext: invalid position\n");
    PPCODE:
        ctxt->proximityPosition = position;

void
setContextSize( self , size )
        SV * self
        int size
    INIT:
        xmlXPathContextPtr ctxt = INT2PTR(xmlXPathContextPtr,SvIV(SvRV(self)));
        if ( ctxt == NULL )
            croak("XPathContext: missing xpath context\n");
        if ( size < -1 )
	    croak("XPathContext: invalid size\n");
    PPCODE:
        ctxt->contextSize = size;
        if ( size == 0 )
	    ctxt->proximityPosition = 0;
	else if ( size > 0 )
	    ctxt->proximityPosition = 1;
        else
	    ctxt->proximityPosition = -1;

void
registerNs( pxpath_context, prefix, ns_uri )
        SV * pxpath_context
        SV * prefix
        SV * ns_uri
    PREINIT:
        xmlXPathContextPtr ctxt = NULL;
    INIT:
        ctxt = INT2PTR(xmlXPathContextPtr,SvIV(SvRV(pxpath_context)));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context\n");
        }
        LibXML_configure_xpathcontext(ctxt);
    PPCODE:
        if(SvOK(ns_uri)) {
	    if(xmlXPathRegisterNs(ctxt, (xmlChar *) SvPV_nolen(prefix),
                                  (xmlChar *) SvPV_nolen(ns_uri)) == -1) {
                croak("XPathContext: cannot register namespace\n");
            }
        } else {
	    if(xmlXPathRegisterNs(ctxt, (xmlChar *) SvPV_nolen(prefix), NULL) == -1) {
                croak("XPathContext: cannot unregister namespace\n");
            }
        }

SV*
lookupNs( pxpath_context, prefix )
        SV * pxpath_context
        SV * prefix
    PREINIT:
        xmlXPathContextPtr ctxt = NULL;
    INIT:
        ctxt = INT2PTR(xmlXPathContextPtr,SvIV(SvRV(pxpath_context)));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context\n");
        }
        LibXML_configure_xpathcontext(ctxt);
    CODE:
        RETVAL = C2Sv(xmlXPathNsLookup(ctxt, (xmlChar *) SvPV_nolen(prefix)), NULL);
    OUTPUT:
        RETVAL

SV*
getVarLookupData( self )
        SV * self
    INIT:
        xmlXPathContextPtr ctxt = INT2PTR(xmlXPathContextPtr,SvIV(SvRV(self)));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context\n");
        }
    CODE:
        if(XPathContextDATA(ctxt)->varData != NULL) {
            RETVAL = newSVsv(XPathContextDATA(ctxt)->varData);
        } else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

SV*
getVarLookupFunc( self )
        SV * self
    INIT:
        xmlXPathContextPtr ctxt = INT2PTR(xmlXPathContextPtr,SvIV(SvRV(self)));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context\n");
        }
    CODE:
        if(XPathContextDATA(ctxt)->varData != NULL) {
            RETVAL = newSVsv(XPathContextDATA(ctxt)->varLookup);
        } else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

void
registerVarLookupFunc( pxpath_context, lookup_func, lookup_data )
        SV * pxpath_context
        SV * lookup_func
        SV * lookup_data
    PREINIT:
        xmlXPathContextPtr ctxt = NULL;
        XPathContextDataPtr data = NULL;
    INIT:
        ctxt = INT2PTR(xmlXPathContextPtr,SvIV(SvRV(pxpath_context)));
        if ( ctxt == NULL )
            croak("XPathContext: missing xpath context\n");
        data = XPathContextDATA(ctxt);
        if ( data == NULL )
            croak("XPathContext: missing xpath context private data\n");
        LibXML_configure_xpathcontext(ctxt);
        /* free previous lookup function and data */
        if (data->varLookup && SvOK(data->varLookup))
            SvREFCNT_dec(data->varLookup);
        if (data->varData && SvOK(data->varData))
            SvREFCNT_dec(data->varData);
        data->varLookup=NULL;
        data->varData=NULL;
    PPCODE:
        if (SvOK(lookup_func)) {
            if ( SvROK(lookup_func) && SvTYPE(SvRV(lookup_func)) == SVt_PVCV ) {
		data->varLookup = newSVsv(lookup_func);
		if (SvOK(lookup_data))
		    data->varData = newSVsv(lookup_data);
		xmlXPathRegisterVariableLookup(ctxt,
					       LibXML_generic_variable_lookup, ctxt);
		if (ctxt->varLookupData==NULL || ctxt->varLookupData != ctxt) {
		    croak( "XPathContext: registration failure\n" );
		}
            } else {
                croak("XPathContext: 1st argument is not a CODE reference\n");
            }
        } else {
            /* unregister */
            xmlXPathRegisterVariableLookup(ctxt, NULL, NULL);
        }

void
registerFunctionNS( pxpath_context, name, uri, func)
        SV * pxpath_context
        char * name
        SV * uri
        SV * func
    PREINIT:
        xmlXPathContextPtr ctxt = NULL;
        SV * pfdr;
        SV * key;
        STRLEN len;
        char *strkey;

    INIT:
        ctxt = INT2PTR(xmlXPathContextPtr,SvIV(SvRV(pxpath_context)));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context\n");
        }
        LibXML_configure_xpathcontext(ctxt);
        if ( !SvOK(func) ||
             (SvOK(func) && ((SvROK(func) && SvTYPE(SvRV(func)) == SVt_PVCV )
                || SvPOK(func)))) {
            if (ctxt->funcLookupData == NULL) {
                if (SvOK(func)) {
                    pfdr = newRV_noinc((SV*) newHV());
                    ctxt->funcLookupData = pfdr;
                } else {
                    /* looks like no perl function was never registered, */
                    /* nothing to unregister */
                    warn("XPathContext: nothing to unregister\n");
                    return;
                }
            } else {
                if (SvTYPE(SvRV((SV *)ctxt->funcLookupData)) == SVt_PVHV) {
                    /* good, it's a HV */
                    pfdr = (SV *)ctxt->funcLookupData;
                } else {
                    croak ("XPathContext: cannot register: funcLookupData structure occupied\n");
                }
            }
            key = newSVpvn("",0);
            if (SvOK(uri)) {
                sv_catpv(key, "{");
                sv_catsv(key, uri);
                sv_catpv(key, "}");
            }
            sv_catpv(key, (const char*)name);
            strkey = SvPV(key, len);
            /* warn("Trying to store function '%s' in %d\n", strkey, pfdr); */
            if (SvOK(func)) {
                (void) hv_store((HV *)SvRV(pfdr),strkey, len, newSVsv(func), 0);
            } else {
                /* unregister */
                (void) hv_delete((HV *)SvRV(pfdr),strkey, len, G_DISCARD);
            }
            SvREFCNT_dec(key);
        } else {
            croak("XPathContext: 3rd argument is not a CODE reference or function name\n");
        }
    PPCODE:
        if (SvOK(uri)) {
	    xmlXPathRegisterFuncNS(ctxt, (xmlChar *) name,
                                   (xmlChar *) SvPV(uri, len),
                                    (SvOK(func) ?
                                    LibXML_generic_extension_function : NULL));
        } else {
            xmlXPathRegisterFunc(ctxt, (xmlChar *) name,
                                 (SvOK(func) ?
                                 LibXML_generic_extension_function : NULL));
        }

void
_free_node_pool( pxpath_context )
        SV * pxpath_context
    PREINIT:
        xmlXPathContextPtr ctxt = NULL;
    INIT:
        ctxt = INT2PTR(xmlXPathContextPtr,SvIV(SvRV(pxpath_context)));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context\n");
        }
    PPCODE:
        if (XPathContextDATA(ctxt)->pool != NULL) {
            SvREFCNT_dec((SV *)XPathContextDATA(ctxt)->pool);
            XPathContextDATA(ctxt)->pool = NULL;
        }

void
_findnodes( pxpath_context, perl_xpath )
        SV * pxpath_context
        SV * perl_xpath
    PREINIT:
        xmlXPathContextPtr ctxt = NULL;
        ProxyNodePtr owner = NULL;
        xmlXPathObjectPtr found = NULL;
        xmlNodeSetPtr nodelist = NULL;
        SV * element = NULL ;
        xmlChar * xpath = NULL;
        xmlXPathCompExprPtr comp = NULL;
        PREINIT_SAVED_ERROR
    INIT:
        ctxt = INT2PTR(xmlXPathContextPtr,SvIV(SvRV(pxpath_context)));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context\n");
        }
        LibXML_configure_xpathcontext(ctxt);
        if ( ctxt->node == NULL ) {
            croak("XPathContext: lost current node\n");
        }
        if (sv_isobject(perl_xpath) && sv_isa(perl_xpath,"XML::LibXML::XPathExpression")) {
             comp = INT2PTR(xmlXPathCompExprPtr,SvIV((SV*)SvRV( perl_xpath )));
             if (!comp) XSRETURN_UNDEF;
        } else {
            xpath = nodeSv2C(perl_xpath, ctxt->node);
            if ( !(xpath && xmlStrlen(xpath)) ) {
                if ( xpath )
                    xmlFree(xpath);
                croak("XPathContext: empty XPath found\n");
                XSRETURN_UNDEF;
            }
        }
    PPCODE:
        INIT_ERROR_HANDLER;

        PUTBACK ;
        if (comp) {
          found = domXPathCompFindCtxt( ctxt, comp, 0 );
        } else {
	  found = domXPathFindCtxt( ctxt, xpath, 0 );
	  xmlFree(xpath);
        }
        SPAGAIN ;

        if (found != NULL) {
          nodelist = found->nodesetval;
        } else {
          nodelist = NULL;
        }
        CLEANUP_ERROR_HANDLER;
        if ( nodelist ) {
	    REPORT_ERROR(1);
            if ( nodelist->nodeNr > 0 ) {
                int i;
                const char * cls = "XML::LibXML::Node";
                xmlNodePtr tnode;
                int l = nodelist->nodeNr;
                for( i = 0  ; i < l; i++){
                    /* we have to create a new instance of an objectptr.
                     * and then place the current node into the new object.
                     * afterwards we can push the object to the array!
                     */
                    element = NULL;
                    tnode = nodelist->nodeTab[i];
                    if (tnode->type == XML_NAMESPACE_DECL) {
                        xmlNsPtr newns = xmlCopyNamespace((xmlNsPtr)tnode);
                        if ( newns != NULL ) {
                            element = NEWSV(0,0);
                            cls = PmmNodeTypeName( tnode );
                            element = sv_setref_pv( element,
                                                    (const char *)cls,
                                                    newns
                                                  );
                        }
                        else {
                            continue;
                        }
                    }
                    else {
                        if (tnode->doc) {
                            owner = PmmOWNERPO(PmmNewNode((xmlNodePtr) tnode->doc));
                        } else {
                            /* we try to find a known node on the ancestor axis */
                            xmlNodePtr n = tnode;
                            while (n && n->_private == NULL) n = n->parent;
                            if (n) owner = PmmOWNERPO(((ProxyNodePtr)n->_private));
                            else owner = NULL; /* self contained node */
                        }
                        element = PmmNodeToSv(tnode, owner);
                    }
                    XPUSHs( sv_2mortal(element) );
                }
            }
            /* prevent libxml2 from freeing the actual nodes */
            if (found->boolval) found->boolval=0;
            xmlXPathFreeObject(found);
        }
        else {
            xmlXPathFreeObject(found);
	    REPORT_ERROR(0);
        }

void
_find( pxpath_context, pxpath, to_bool )
        SV * pxpath_context
        SV * pxpath
        int to_bool
    PREINIT:
        xmlXPathContextPtr ctxt = NULL;
        ProxyNodePtr owner = NULL;
        xmlXPathObjectPtr found = NULL;
        xmlNodeSetPtr nodelist = NULL;
        xmlChar * xpath = NULL;
        xmlXPathCompExprPtr comp = NULL;
        PREINIT_SAVED_ERROR
    INIT:
        ctxt = INT2PTR(xmlXPathContextPtr,SvIV(SvRV(pxpath_context)));
        if ( ctxt == NULL ) {
            croak("XPathContext: missing xpath context\n");
        }
        LibXML_configure_xpathcontext(ctxt);
        if ( ctxt->node == NULL ) {
            croak("XPathContext: lost current node\n");
        }
        if (sv_isobject(pxpath) && sv_isa(pxpath,"XML::LibXML::XPathExpression")) {
             comp = INT2PTR(xmlXPathCompExprPtr,SvIV((SV*)SvRV( pxpath )));
             if (!comp) XSRETURN_UNDEF;
        } else {
            xpath = nodeSv2C(pxpath, ctxt->node);
            if ( !(xpath && xmlStrlen(xpath)) ) {
                if ( xpath )
                    xmlFree(xpath);
                croak("XPathContext: empty XPath found\n");
                XSRETURN_UNDEF;
            }
        }
    PPCODE:
        INIT_ERROR_HANDLER;
        PUTBACK ;
        if (comp) {
          found = domXPathCompFindCtxt( ctxt, comp, to_bool );
        } else {
	  found = domXPathFindCtxt( ctxt, xpath, to_bool );
	  xmlFree(xpath);
        }
        SPAGAIN ;
        CLEANUP_ERROR_HANDLER;
        if (found) {
	    REPORT_ERROR(1);
            switch (found->type) {
                case XPATH_NODESET:
                    /* return as a NodeList */
                    /* access ->nodesetval */
                    XPUSHs(sv_2mortal(newSVpv("XML::LibXML::NodeList", 0)));
                    nodelist = found->nodesetval;
                    if ( nodelist ) {
                        if ( nodelist->nodeNr > 0 ) {
                            int i;
                            const char * cls = "XML::LibXML::Node";
                            xmlNodePtr tnode;
                            SV * element;
                            int l = nodelist->nodeNr;

                            for( i = 0 ; i < l; i++){
                                /* we have to create a new instance of an
                                 * objectptr. and then
                                 * place the current node into the new
                                 * object. afterwards we can
                                 * push the object to the array!
                                 */
                                tnode = nodelist->nodeTab[i];

                                /* let's be paranoid */
                                if (tnode->type == XML_NAMESPACE_DECL) {
                                     xmlNsPtr newns = xmlCopyNamespace((xmlNsPtr)tnode);
                                    if ( newns != NULL ) {
                                        element = NEWSV(0,0);
                                        cls = PmmNodeTypeName( tnode );
                                        element = sv_setref_pv( element,
                                                                (const char *)cls,
                                                                (void*)newns
                                                          );
                                    }
                                    else {
                                        continue;
                                    }
                                }
                                else {
                                    if (tnode->doc) {
                                        owner = PmmOWNERPO(PmmNewNode((xmlNodePtr) tnode->doc));
                                    } else {
                                        /* we try to find a known node on the ancestor axis */
                                        xmlNodePtr n = tnode;
                                        while (n && n->_private == NULL) n = n->parent;
                                        if (n) owner = PmmOWNERPO(((ProxyNodePtr)n->_private));
                                        else owner = NULL;  /* self contained node */
                                    }
                                    element = PmmNodeToSv(tnode, owner);
                                }
                                XPUSHs( sv_2mortal(element) );
                            }
                        }
                    }
                    /* prevent libxml2 from freeing the actual nodes */
                    if (found->boolval) found->boolval=0;
                    break;
                case XPATH_BOOLEAN:
                    /* return as a Boolean */
                    /* access ->boolval */
                    XPUSHs(sv_2mortal(newSVpv("XML::LibXML::Boolean", 0)));
                    XPUSHs(sv_2mortal(newSViv(found->boolval)));
                    break;
                case XPATH_NUMBER:
                    /* return as a Number */
                    /* access ->floatval */
                    XPUSHs(sv_2mortal(newSVpv("XML::LibXML::Number", 0)));
                    XPUSHs(sv_2mortal(newSVnv(found->floatval)));
                    break;
                case XPATH_STRING:
                    /* access ->stringval */
                    /* return as a Literal */
                    XPUSHs(sv_2mortal(newSVpv("XML::LibXML::Literal", 0)));
                    XPUSHs(sv_2mortal(C2Sv(found->stringval, NULL)));
                    break;
                default:
                    croak("Unknown XPath return type");
            }
            xmlXPathFreeObject(found);
        }
        else {
	    REPORT_ERROR(0);
        }

MODULE = XML::LibXML         PACKAGE = XML::LibXML::InputCallback

void
lib_cleanup_callbacks( self )
    CODE:
        xmlCleanupInputCallbacks();
        xmlRegisterDefaultInputCallbacks();

void
lib_init_callbacks( self )
    CODE:
        xmlRegisterDefaultInputCallbacks(); /* important */
        xmlRegisterInputCallbacks((xmlInputMatchCallback) LibXML_input_match,
                                  (xmlInputOpenCallback) LibXML_input_open,
                                  (xmlInputReadCallback) LibXML_input_read,
                                  (xmlInputCloseCallback) LibXML_input_close);

#ifdef HAVE_READER_SUPPORT

MODULE = XML::LibXML	PACKAGE = XML::LibXML::Reader

xmlTextReaderPtr
_newForFile(CLASS, filename, encoding, options)
	const char* CLASS
	const char* filename
	const char * encoding = SvOK($arg) ? SvPV_nolen($arg) : NULL;
	int options = SvOK($arg) ? SvIV($arg) : 0;
    CODE:
        RETVAL = xmlReaderForFile(filename, encoding, options);
	INIT_READER_ERROR_HANDLER(RETVAL);
    OUTPUT:
	RETVAL

xmlTextReaderPtr
_newForIO(CLASS, fh, url, encoding, options)
	const char* CLASS
	SV * fh
	const char * url = SvOK($arg) ? SvPV_nolen($arg) : NULL;
	const char * encoding = SvOK($arg) ? SvPV_nolen($arg) : NULL;
	int options = SvOK($arg) ? SvIV($arg) : 0;
    CODE:
        (void)SvREFCNT_inc(fh); /* _dec'd by LibXML_close_perl */
        RETVAL = xmlReaderForIO((xmlInputReadCallback) LibXML_read_perl,
				(xmlInputCloseCallback) LibXML_close_perl,
				(void *) fh, url, encoding, options);
	INIT_READER_ERROR_HANDLER(RETVAL)
    OUTPUT:
	RETVAL

xmlTextReaderPtr
_newForString(CLASS, string, url, encoding, options)
	const char* CLASS
	SV * string
	const char * url = SvOK($arg) ? SvPV_nolen($arg) : NULL;
	const char * encoding = SvOK($arg) ? SvPV_nolen($arg) : NULL;
	int options = SvOK($arg) ? SvIV($arg) : 0;
    CODE:
        if (encoding == NULL && SvUTF8( string )) {
	  encoding = "UTF-8";
        }
        RETVAL = xmlReaderForDoc((xmlChar* )SvPV_nolen(string), url, encoding, options);
        INIT_READER_ERROR_HANDLER(RETVAL)
    OUTPUT:
	RETVAL

xmlTextReaderPtr
_newForFd(CLASS, fd, url, encoding, options)
	const char* CLASS
	int fd
	const char * url = SvOK($arg) ? SvPV_nolen($arg) : NULL;
	const char * encoding = SvOK($arg) ? SvPV_nolen($arg) : NULL;
	int options = SvOK($arg) ? SvIV($arg) : 0;
    CODE:
        RETVAL = xmlReaderForFd(fd, url, encoding, options);
	INIT_READER_ERROR_HANDLER(RETVAL)
    OUTPUT:
	RETVAL

xmlTextReaderPtr
_newForDOM(CLASS, perl_doc)
	const char* CLASS
	SV * perl_doc
    CODE:
        PmmREFCNT_inc(SvPROXYNODE(perl_doc)); /* _dec in DESTROY */
        RETVAL = xmlReaderWalker((xmlDocPtr) PmmSvNode(perl_doc));
    OUTPUT:
	RETVAL

int
attributeCount(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderAttributeCount(reader);
    OUTPUT:
	RETVAL

SV *
baseURI(reader)
	xmlTextReaderPtr reader
    PREINIT:
	const xmlChar *result = NULL;
    CODE:
	result = xmlTextReaderConstBaseUri(reader);
	RETVAL = C2Sv(result, NULL);
    OUTPUT:
	RETVAL

long
byteConsumed(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderByteConsumed(reader);
    OUTPUT:
	RETVAL

int
_close(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderClose(reader);
    OUTPUT:
	RETVAL

SV *
encoding(reader)
	xmlTextReaderPtr reader
    PREINIT:
	const xmlChar *result = NULL;
    CODE:
	result = xmlTextReaderConstEncoding(reader);
	RETVAL = C2Sv(result, NULL);
    OUTPUT:
	RETVAL

SV *
localName(reader)
	xmlTextReaderPtr reader
    PREINIT:
	const xmlChar *result = NULL;
    CODE:
	result = xmlTextReaderConstLocalName(reader);
	RETVAL = C2Sv(result, NULL);
    OUTPUT:
	RETVAL

SV *
name(reader)
	xmlTextReaderPtr reader
    PREINIT:
	const xmlChar *result = NULL;
    CODE:
	result = xmlTextReaderConstName(reader);
	RETVAL = C2Sv(result, NULL);
    OUTPUT:
	RETVAL

SV *
namespaceURI(reader)
	xmlTextReaderPtr reader
    PREINIT:
	const xmlChar *result = NULL;
    CODE:
	result = xmlTextReaderConstNamespaceUri(reader);
	RETVAL = C2Sv(result, NULL);
    OUTPUT:
	RETVAL

SV *
prefix(reader)
	xmlTextReaderPtr reader
    PREINIT:
	const xmlChar *result = NULL;
    CODE:
	result = xmlTextReaderConstPrefix(reader);
	RETVAL = C2Sv(result, NULL);
    OUTPUT:
	RETVAL

SV *
value(reader)
	xmlTextReaderPtr reader
    PREINIT:
	const xmlChar *result = NULL;
    CODE:
	result = xmlTextReaderConstValue(reader);
	RETVAL = C2Sv(result, NULL);
    OUTPUT:
	RETVAL

SV *
xmlLang(reader)
	xmlTextReaderPtr reader
    PREINIT:
	const xmlChar *result = NULL;
    CODE:
	result = xmlTextReaderConstXmlLang(reader);
	RETVAL = C2Sv(result, NULL);
    OUTPUT:
	RETVAL


SV *
xmlVersion(reader)
	xmlTextReaderPtr reader
    PREINIT:
	const xmlChar *result = NULL;
    CODE:
	result = xmlTextReaderConstXmlVersion(reader);
	RETVAL = C2Sv(result, NULL);
    OUTPUT:
	RETVAL


int
depth(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderDepth(reader);
    OUTPUT:
	RETVAL


SV *
getAttribute(reader, name)
	xmlTextReaderPtr reader
	char * name
    PREINIT:
	xmlChar *result = NULL;
    CODE:
	result = xmlTextReaderGetAttribute(reader, (xmlChar*) name);
	RETVAL = C2Sv(result, NULL);
        xmlFree(result);
    OUTPUT:
	RETVAL

SV *
getAttributeNo(reader, no)
	xmlTextReaderPtr reader
	int no
    PREINIT:
	xmlChar *result = NULL;
    CODE:
	result = xmlTextReaderGetAttributeNo(reader, no);
	RETVAL = C2Sv(result, NULL);
        xmlFree(result);
    OUTPUT:
	RETVAL

SV *
getAttributeNs(reader, localName, namespaceURI)
	xmlTextReaderPtr reader
	char * localName
        char * namespaceURI = SvOK($arg) ? SvPV_nolen($arg) : NULL;
    PREINIT:
	xmlChar *result = NULL;
    CODE:
	result = xmlTextReaderGetAttributeNs(reader,  (xmlChar*) localName,
					     (xmlChar*) namespaceURI);
	RETVAL = C2Sv(result, NULL);
        xmlFree(result);
    OUTPUT:
	RETVAL

int
columnNumber(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderGetParserColumnNumber(reader);
    OUTPUT:
	RETVAL

int
lineNumber(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderGetParserLineNumber(reader);
    OUTPUT:
	RETVAL

int
_getParserProp(reader, prop)
	xmlTextReaderPtr reader
	int prop
    CODE:
	RETVAL = xmlTextReaderGetParserProp(reader, prop);
    OUTPUT:
	RETVAL

int
hasAttributes(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderHasAttributes(reader);
    OUTPUT:
	RETVAL

int
hasValue(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderHasValue(reader);
    OUTPUT:
	RETVAL

SV*
getAttributeHash(reader)
	xmlTextReaderPtr reader
    PREINIT:
	HV* hv;
	SV* sv;
	const xmlChar* name;
	PREINIT_SAVED_ERROR
    CODE:
	INIT_ERROR_HANDLER;
	hv=newHV();
	if (xmlTextReaderHasAttributes(reader) && xmlTextReaderMoveToFirstAttribute(reader)==1) {
	  do {
	    name = xmlTextReaderConstName(reader);
	    sv=C2Sv((xmlTextReaderConstValue(reader)),NULL);
	    if (sv && hv_store(hv, (const char*) name, xmlStrlen(name), sv, 0)==NULL) {
	      SvREFCNT_dec(sv);  /* free if not needed by hv_stores */
	    }
	  } while (xmlTextReaderMoveToNextAttribute(reader)==1);
	  xmlTextReaderMoveToElement(reader);
	}
        RETVAL=newRV_noinc((SV*)hv);
        CLEANUP_ERROR_HANDLER;
	REPORT_ERROR(0);
    OUTPUT:
	RETVAL

int
isDefault(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderIsDefault(reader);
    OUTPUT:
	RETVAL

int
isEmptyElement(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderIsEmptyElement(reader);
    OUTPUT:
	RETVAL

int
isNamespaceDecl(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderIsNamespaceDecl(reader);
    OUTPUT:
	RETVAL

int
isValid(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderIsValid(reader);
    OUTPUT:
	RETVAL

SV *
lookupNamespace(reader, prefix)
	xmlTextReaderPtr reader
	char * prefix = SvOK($arg) ? SvPV_nolen($arg) : NULL;
    PREINIT:
	xmlChar *result = NULL;
    CODE:
	result = xmlTextReaderLookupNamespace(reader, (xmlChar*) prefix);
	RETVAL = C2Sv(result, NULL);
        xmlFree(result);
    OUTPUT:
	RETVAL


int
moveToAttribute(reader, name)
	xmlTextReaderPtr reader
	char * name
    CODE:
	RETVAL = xmlTextReaderMoveToAttribute(reader, (xmlChar*) name);
    OUTPUT:
	RETVAL

int
moveToAttributeNo(reader, no)
	xmlTextReaderPtr reader
	int no
    CODE:
	RETVAL = xmlTextReaderMoveToAttributeNo(reader, no);
    OUTPUT:
	RETVAL

int
moveToAttributeNs(reader, localName, namespaceURI)
	xmlTextReaderPtr reader
	char * localName
	char * namespaceURI = SvOK($arg) ? SvPV_nolen($arg) : NULL;
    CODE:
	RETVAL = xmlTextReaderMoveToAttributeNs(reader,
						(xmlChar*) localName, (xmlChar*) namespaceURI);
    OUTPUT:
	RETVAL

int
moveToElement(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderMoveToElement(reader);
    OUTPUT:
	RETVAL

int
moveToFirstAttribute(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderMoveToFirstAttribute(reader);
    OUTPUT:
	RETVAL

int
moveToNextAttribute(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderMoveToNextAttribute(reader);
    OUTPUT:
	RETVAL

int
next(reader)
	xmlTextReaderPtr reader
    PREINIT:
	PREINIT_SAVED_ERROR
    CODE:
	INIT_ERROR_HANDLER;
	RETVAL = xmlTextReaderNext(reader);
        CLEANUP_ERROR_HANDLER;
	REPORT_ERROR(0);
    OUTPUT:
	RETVAL

#define LIBXML_READER_NEXT_SIBLING(ret,reader)	\
	ret = xmlTextReaderNextSibling(reader); \
        if (ret == -1)                          \
        {			                \
	  int depth;				\
          depth = xmlTextReaderDepth(reader);	\
	  ret = xmlTextReaderRead(reader);			   \
	  while (ret == 1 && xmlTextReaderDepth(reader) > depth) { \
	    ret = xmlTextReaderNext(reader);			   \
	  }							   \
	  if (ret == 1) {					   \
	    if (xmlTextReaderDepth(reader) != depth) {		   \
	      ret = 0;							\
	    } else if (xmlTextReaderNodeType(reader) == XML_READER_TYPE_END_ELEMENT) { \
	      ret = xmlTextReaderRead(reader);				\
	    }								\
	  }								\
        }

int
nextSibling(reader)
	xmlTextReaderPtr reader
    PREINIT:
	PREINIT_SAVED_ERROR
    CODE:
	INIT_ERROR_HANDLER;
	LIBXML_READER_NEXT_SIBLING(RETVAL,reader)
        CLEANUP_ERROR_HANDLER;
	REPORT_ERROR(0);
    OUTPUT:
	RETVAL

int
nextSiblingElement(reader, name = NULL, nsURI = NULL)
	xmlTextReaderPtr reader
	const char * name
	const char * nsURI
    PREINIT:
	PREINIT_SAVED_ERROR
    CODE:
	INIT_ERROR_HANDLER;
	do {
	  LIBXML_READER_NEXT_SIBLING(RETVAL,reader)
	  if (LIBXML_READER_TEST_ELEMENT(reader,name,nsURI)) {
	    break;
	  }
	} while (RETVAL == 1);
        CLEANUP_ERROR_HANDLER;
	REPORT_ERROR(0);
    OUTPUT:
	RETVAL

int
nextElement(reader, name = NULL, nsURI = NULL)
	xmlTextReaderPtr reader
	const char * name
	const char * nsURI
    PREINIT:
	PREINIT_SAVED_ERROR
    CODE:
	INIT_ERROR_HANDLER;
	do {
	  RETVAL = xmlTextReaderRead(reader);
	  if (LIBXML_READER_TEST_ELEMENT(reader,name,nsURI)) {
	    break;
	  }
	} while (RETVAL == 1);
        CLEANUP_ERROR_HANDLER;
	REPORT_ERROR(0);
    OUTPUT:
	RETVAL

int
nextPatternMatch(reader, compiled)
	xmlTextReaderPtr reader
	xmlPatternPtr compiled
    PREINIT:
	PREINIT_SAVED_ERROR
	xmlNodePtr node = NULL;
    CODE:
        if ( compiled == NULL )
	   croak("Usage: $reader->nextPatternMatch( a-XML::LibXML::Pattern-object )");
	do {
	  RETVAL = xmlTextReaderRead(reader);
          node = xmlTextReaderCurrentNode(reader);
	  if (node && xmlPatternMatch(compiled, node)) {
	    break;
	  }
	} while (RETVAL == 1);
        CLEANUP_ERROR_HANDLER;
	REPORT_ERROR(0);
    OUTPUT:
	RETVAL

int
skipSiblings(reader)
	xmlTextReaderPtr reader
    PREINIT:
        int depth;
    PREINIT:
	PREINIT_SAVED_ERROR
    CODE:
	INIT_ERROR_HANDLER;
        depth = xmlTextReaderDepth(reader);
        RETVAL = -1;
        if (depth > 0) {
          do {
   	     RETVAL = xmlTextReaderNext(reader);
	  } while (RETVAL == 1 && xmlTextReaderDepth(reader) >= depth);
	  if (xmlTextReaderNodeType(reader) != XML_READER_TYPE_END_ELEMENT) {
	    RETVAL = -1;
	  }
        }
        CLEANUP_ERROR_HANDLER;
	REPORT_ERROR(0);
    OUTPUT:
	RETVAL

int
nodeType(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderNodeType(reader);
    OUTPUT:
	RETVAL

SV*
quoteChar(reader)
	xmlTextReaderPtr reader
    PREINIT:
        int ret;
    CODE:
	ret = xmlTextReaderQuoteChar(reader);
        if (ret == -1) XSRETURN_UNDEF;
        RETVAL = newSVpvf("%c",ret);
    OUTPUT:
	RETVAL

int
read(reader)
	xmlTextReaderPtr reader
    PREINIT:
	PREINIT_SAVED_ERROR
    CODE:
	INIT_ERROR_HANDLER;
	RETVAL = xmlTextReaderRead(reader);
        CLEANUP_ERROR_HANDLER;
	REPORT_ERROR(0);
    OUTPUT:
	RETVAL

int
readAttributeValue(reader)
	xmlTextReaderPtr reader
    PREINIT:
	PREINIT_SAVED_ERROR
    CODE:
	INIT_ERROR_HANDLER;
	RETVAL = xmlTextReaderReadAttributeValue(reader);
        CLEANUP_ERROR_HANDLER;
	REPORT_ERROR(0);
    OUTPUT:
	RETVAL


SV *
readInnerXml(reader)
	xmlTextReaderPtr reader
    PREINIT:
	xmlChar *result = NULL;
    PREINIT:
	PREINIT_SAVED_ERROR
    CODE:
	INIT_ERROR_HANDLER;
	result = xmlTextReaderReadInnerXml(reader);
        CLEANUP_ERROR_HANDLER;
	REPORT_ERROR(0);
        if (!result) XSRETURN_UNDEF;
	RETVAL = C2Sv(result, NULL);
        xmlFree(result);
    OUTPUT:
	RETVAL

SV *
readOuterXml(reader)
	xmlTextReaderPtr reader
    PREINIT:
	xmlChar *result = NULL;
    PREINIT:
	PREINIT_SAVED_ERROR
    CODE:
	INIT_ERROR_HANDLER;
	result = xmlTextReaderReadOuterXml(reader);
	CLEANUP_ERROR_HANDLER;
	REPORT_ERROR(0);
        if (result) {
	  RETVAL = C2Sv(result, NULL);
	  xmlFree(result);
	} else {
           XSRETURN_UNDEF;
	}
    OUTPUT:
	RETVAL

int
readState(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderReadState(reader);
    OUTPUT:
	RETVAL

int
_setParserProp(reader, prop, value)
	xmlTextReaderPtr reader
	int prop
	int value
    CODE:
	RETVAL = xmlTextReaderSetParserProp(reader, prop, value);
    OUTPUT:
	RETVAL

int
standalone(reader)
	xmlTextReaderPtr reader
    CODE:
	RETVAL = xmlTextReaderStandalone(reader);
    OUTPUT:
	RETVAL

SV *
_nodePath(reader)
	xmlTextReaderPtr reader
    PREINIT:
	xmlNodePtr node = NULL;
        xmlChar * path = NULL;
    CODE:
        node = xmlTextReaderCurrentNode(reader);
        if ( node ==NULL ) {
          XSRETURN_UNDEF;
	}
	path = xmlGetNodePath( node );
        if ( path == NULL ) {
          XSRETURN_UNDEF;
        }
        RETVAL = C2Sv(path,NULL);
	xmlFree(path);
    OUTPUT:
        RETVAL

#ifdef LIBXML_PATTERN_ENABLED

int
matchesPattern(reader, compiled)
	xmlTextReaderPtr reader
        xmlPatternPtr compiled
    PREINIT:
	xmlNodePtr node = NULL;
    CODE:
        if ( compiled == NULL )
	   XSRETURN_UNDEF;
        node = xmlTextReaderCurrentNode(reader);
        if ( node ==NULL ) {
          XSRETURN_UNDEF;
	}
	RETVAL = xmlPatternMatch(compiled, node);
    OUTPUT:
        RETVAL

#endif /* LIBXML_PATTERN_ENABLED */

SV *
copyCurrentNode(reader,expand = 0)
	xmlTextReaderPtr reader
        int expand
    PREINIT:
	xmlNodePtr node = NULL;
	xmlNodePtr copy;
        xmlDocPtr  doc = NULL;
        ProxyNodePtr proxy;
    PREINIT:
	PREINIT_SAVED_ERROR
    CODE:
	INIT_ERROR_HANDLER;
	if (expand) {
	  node = xmlTextReaderExpand(reader);
        }
	else {
	  node = xmlTextReaderCurrentNode(reader);
	}
        if (node) {
	  doc = xmlTextReaderCurrentDoc(reader);
        }
        if (!doc) {
          CLEANUP_ERROR_HANDLER;
	  REPORT_ERROR(0);
          XSRETURN_UNDEF;
	}
        if (xmlTextReaderGetParserProp(reader,XML_PARSER_VALIDATE))
            PmmInvalidatePSVI(doc); /* the document may have psvi info */

        copy = PmmCloneNode( node, expand );
        if ( copy == NULL ) {
            CLEANUP_ERROR_HANDLER;
	    REPORT_ERROR(0);
            XSRETURN_UNDEF;
        }
        if ( copy->type  == XML_DTD_NODE ) {
            RETVAL = PmmNodeToSv(copy, NULL);
        }
        else {
	    ProxyNodePtr docfrag = NULL;

            if ( doc != NULL ) {
                xmlSetTreeDoc(copy, doc);
            }
            proxy = PmmNewNode((xmlNodePtr)doc);
            if (PmmREFCNT(proxy) == 0) {
                PmmREFCNT_inc(proxy);
            }
            LibXML_set_reader_preserve_flag(reader);

            docfrag = PmmNewFragment( doc );
            xmlAddChild( PmmNODE(docfrag), copy );
            RETVAL = PmmNodeToSv(copy, docfrag);
        }
        CLEANUP_ERROR_HANDLER;
	REPORT_ERROR(0);
    OUTPUT:
        RETVAL

SV *
document(reader)
	xmlTextReaderPtr reader
    PREINIT:
	xmlDocPtr doc = NULL;
    CODE:
	doc = xmlTextReaderCurrentDoc(reader);
        if (!doc) XSRETURN_UNDEF;
        RETVAL = PmmNodeToSv((xmlNodePtr)doc, NULL);
        /* FIXME: taint the document with PmmInvalidatePSVI if the reader did validation */
        if ( PmmREFCNT(SvPROXYNODE(RETVAL))==1 ) {
	  /* will be decremented in Reader destructor */
	  PmmREFCNT_inc(SvPROXYNODE(RETVAL));
	}
        if (xmlTextReaderGetParserProp(reader,XML_PARSER_VALIDATE))
            PmmInvalidatePSVI(doc); /* the document may have psvi info */

        LibXML_set_reader_preserve_flag(reader);

    OUTPUT:
        RETVAL

int
_preservePattern(reader,pattern,ns_map=NULL)
	xmlTextReaderPtr reader
        char * pattern
        AV * ns_map
    PREINIT:
        xmlChar** namespaces = NULL;
	SV** aux;
        int last,i;
    CODE:
        if (ns_map) {
          last = av_len(ns_map);
          New(0,namespaces, last+2, xmlChar*);
          for( i = 0; i <= last ; i++ ) {
              aux = av_fetch(ns_map,i,0);
	      namespaces[i]=(xmlChar*) SvPV_nolen(*aux);
          }
	  namespaces[i]=0;
	}
	RETVAL = xmlTextReaderPreservePattern(reader,(const xmlChar*) pattern,
					      (const xmlChar**)namespaces);
        Safefree(namespaces);
    OUTPUT:
        RETVAL

SV *
preserveNode(reader)
	xmlTextReaderPtr reader
    PREINIT:
        xmlNodePtr node;
        xmlDocPtr doc;
        ProxyNodePtr proxy;
	PREINIT_SAVED_ERROR
    CODE:
	INIT_ERROR_HANDLER;
	doc = xmlTextReaderCurrentDoc(reader);
        if (!doc) {
	  CLEANUP_ERROR_HANDLER;
	  REPORT_ERROR(0);
	  XSRETURN_UNDEF;
	}
    proxy = PmmNewNode((xmlNodePtr)doc);
    if ( PmmREFCNT(proxy) == 0 ) {
	  /* new proxy node */
	  PmmREFCNT_inc(proxy);
	}
        LibXML_set_reader_preserve_flag(reader);

	node = xmlTextReaderPreserve(reader);
        CLEANUP_ERROR_HANDLER;
	REPORT_ERROR(0);
        if (node) {
           RETVAL = PmmNodeToSv(node, proxy);
	} else {
	    XSRETURN_UNDEF;
	}
    OUTPUT:
        RETVAL

int
finish(reader)
	xmlTextReaderPtr reader
    PREINIT:
	PREINIT_SAVED_ERROR
    CODE:
	INIT_ERROR_HANDLER;
	while (1) {
	  RETVAL = xmlTextReaderRead(reader);
	  if (RETVAL!=1) break;
	}
        CLEANUP_ERROR_HANDLER;
	REPORT_ERROR(0);
        RETVAL++; /* we want 0 - fail, 1- success */
    OUTPUT:
	RETVAL

#ifdef HAVE_SCHEMAS

int
_setRelaxNGFile(reader,rng)
	xmlTextReaderPtr reader
	char* rng
    CODE:
	RETVAL = xmlTextReaderRelaxNGValidate(reader,rng);
    OUTPUT:
	RETVAL

int
_setRelaxNG(reader,rng_doc)
	xmlTextReaderPtr reader
	xmlRelaxNGPtr rng_doc
    CODE:
	RETVAL = xmlTextReaderRelaxNGSetSchema(reader,rng_doc);
    OUTPUT:
	RETVAL

int
_setXSDFile(reader,xsd)
	xmlTextReaderPtr reader
	char* xsd
    CODE:
	RETVAL = xmlTextReaderSchemaValidate(reader,xsd);
    OUTPUT:
	RETVAL

int
_setXSD(reader,xsd_doc)
	xmlTextReaderPtr reader
	xmlSchemaPtr xsd_doc
    CODE:
	RETVAL =  xmlTextReaderSetSchema(reader,xsd_doc);
    OUTPUT:
	RETVAL

#endif /* HAVE_SCHEMAS */

void
_DESTROY(reader)
	xmlTextReaderPtr reader
    PREINIT:
        xmlDocPtr doc;
        ProxyNodePtr proxy;
	/* SV * error_sv = NULL;
           xmlTextReaderErrorFunc f = NULL; */
    CODE:

    if ( LibXML_get_reader_preserve_flag(reader) ) {
        doc = xmlTextReaderCurrentDoc(reader);
        if (doc) {
            proxy = PmmNewNode((xmlNodePtr)doc);
            if ( PmmREFCNT(proxy) == 0 ) {
                PmmREFCNT_inc(proxy);
            }
            PmmREFCNT_dec(proxy);
        }
    }
        if (xmlTextReaderReadState(reader) != XML_TEXTREADER_MODE_CLOSED) {
	  xmlTextReaderClose(reader);
	}
        /* xmlTextReaderGetErrorHandler(reader, &f, (void **) &error_sv);
        if (error_sv) {
           sv_2mortal(error_sv);
	} */
	xmlFreeTextReader(reader);

#endif /* HAVE_READER_SUPPORT */

#ifdef WITH_SERRORS

MODULE = XML::LibXML       PACKAGE = XML::LibXML::LibError

int
domain( self )
        xmlErrorPtr self
    CODE:
        RETVAL = self->domain;
    OUTPUT:
        RETVAL

int
code( self )
        xmlErrorPtr self
    CODE:
        RETVAL = self->code;
    OUTPUT:
        RETVAL

int
line( self )
        xmlErrorPtr self
    CODE:
        RETVAL = self->line;
    OUTPUT:
        RETVAL

int
num1( self )
        xmlErrorPtr self
    ALIAS:
        int1 = 1
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = self->int1;
    OUTPUT:
        RETVAL

int
num2( self )
        xmlErrorPtr self
    ALIAS:
        int2 = 1
    CODE:
        PERL_UNUSED_VAR(ix);
        RETVAL = self->int2;
    OUTPUT:
        RETVAL

int
level( self )
        xmlErrorPtr self
    CODE:
        RETVAL = (int)self->level;
    OUTPUT:
        RETVAL

char *
message( self )
        xmlErrorPtr self
    CODE:
        RETVAL = self->message;
    OUTPUT:
        RETVAL

char *
file( self )
        xmlErrorPtr self
    CODE:
        RETVAL = (char*)self->file;
    OUTPUT:
        RETVAL

char *
str1( self )
        xmlErrorPtr self
    CODE:
        RETVAL = (char*)self->str1;
    OUTPUT:
        RETVAL

char *
str2( self )
        xmlErrorPtr self
    CODE:
        RETVAL = (char*)self->str2;
    OUTPUT:
        RETVAL

char *
str3( self )
        xmlErrorPtr self
    CODE:
        RETVAL = (char*)self->str3;
    OUTPUT:
        RETVAL

void
context_and_column( self )
        xmlErrorPtr self
   PREINIT:
        xmlParserInputPtr input;
	const xmlChar *cur, *base, *col_cur;
	unsigned int n, col;	/* GCC warns if signed, because compared with sizeof() */
	xmlChar  content[81]; /* space for 80 chars + line terminator */
	xmlChar *ctnt;
	int domain;
        xmlParserCtxtPtr ctxt = NULL;
   PPCODE:
	domain = self->domain;
	if ((domain == XML_FROM_PARSER) || (domain == XML_FROM_HTML) ||
	    (domain == XML_FROM_DTD) || (domain == XML_FROM_NAMESPACE) ||
	    (domain == XML_FROM_IO) || (domain == XML_FROM_VALID)) {
	  ctxt = (xmlParserCtxtPtr) self->ctxt;
	}
       if (ctxt == NULL) XSRETURN_EMPTY;
       input = ctxt->input;
       if ((input != NULL) && (input->filename == NULL) &&
            (ctxt->inputNr > 1)) {
            input = ctxt->inputTab[ctxt->inputNr - 2];
        }
        if (input == NULL) XSRETURN_EMPTY;
	cur = input->cur;
	base = input->base;
	/* skip backwards over any end-of-lines */
	while ((cur > base) && ((*(cur) == '\n') || (*(cur) == '\r'))) {
	  cur--;
	}
        n = 0;
        /* search backwards for beginning-of-line (to max buff size) */
        while ((n++ < (sizeof(content)-1)) && (cur > base) &&
	       (*(cur) != '\n') && (*(cur) != '\r'))
	  cur--;
	/* search backwards for beginning-of-line for calculating the
	 * column. */
	col_cur = cur;
	while ((col_cur > base) && (*(col_cur) != '\n') && (*(col_cur) != '\r'))
	  col_cur--;
	if ((*(cur) == '\n') || (*(cur) == '\r')) cur++;
	if ((*(col_cur) == '\n') || (*(col_cur) == '\r')) col_cur++;
	/* calculate the error position in terms of the current position */
	col = input->cur - col_cur;
	/* search forward for end-of-line (to max buff size) */
	n = 0;
	ctnt = content;
	/* copy selected text to our buffer */
	while ((*cur != 0) && (*(cur) != '\n') &&
	       (*(cur) != '\r') && (n < sizeof(content)-1)) {
	  *ctnt++ = *cur++;
	  n++;
	}
	*ctnt = 0;
        EXTEND(SP,2);
        PUSHs(sv_2mortal(C2Sv(content, NULL)));
        PUSHs(sv_2mortal(newSViv(col)));

#endif /* WITH_SERRORS */


#ifdef LIBXML_PATTERN_ENABLED

MODULE = XML::LibXML       PACKAGE = XML::LibXML::Pattern

xmlPatternPtr
_compilePattern(CLASS, ppattern, pattern_type, ns_map=NULL)
        SV * ppattern
        AV * ns_map
	int pattern_type
    PREINIT:
        xmlChar * pattern = Sv2C(ppattern, NULL);
        xmlChar** namespaces = NULL;
	SV** aux;
        int last,i;
	PREINIT_SAVED_ERROR
    CODE:
        if ( pattern == NULL )
	   XSRETURN_UNDEF;
        if (ns_map) {
          last = av_len(ns_map);
          New(0,namespaces, last+2, xmlChar*);
          for( i = 0; i <= last ; i++ ) {
              aux = av_fetch(ns_map,i,0);
	      namespaces[i]=(xmlChar*) SvPV_nolen(*aux);
          }
	  namespaces[i]=0;
	}
	INIT_ERROR_HANDLER;
	RETVAL = xmlPatterncompile(pattern, NULL, pattern_type, (const xmlChar **) namespaces);
        Safefree(namespaces);
        xmlFree( pattern );
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(0);
        if ( RETVAL == NULL ) {
	  croak("Compilation of pattern failed");
	}
    OUTPUT:
	RETVAL

int
matchesNode(self, node)
        xmlPatternPtr self
	xmlNodePtr node
    CODE:
        if ( node ==NULL ) {
          XSRETURN_UNDEF;
	}
	RETVAL = xmlPatternMatch(self, node);
    OUTPUT:
        RETVAL

void
DESTROY( self )
        xmlPatternPtr self
    CODE:
        xs_warn( "DESTROY PATTERN OBJECT" );
   	xmlFreePattern(self);

#endif /* LIBXML_PATTERN_ENABLED */

#ifdef LIBXML_REGEXP_ENABLED

MODULE = XML::LibXML       PACKAGE = XML::LibXML::RegExp

xmlRegexpPtr
_compile(CLASS, pregexp)
        SV * pregexp
    PREINIT:
        xmlChar * regexp = Sv2C(pregexp, NULL);
	PREINIT_SAVED_ERROR
    CODE:
        if ( regexp == NULL )
	   XSRETURN_UNDEF;
	INIT_ERROR_HANDLER;
	RETVAL = xmlRegexpCompile(regexp);
        xmlFree( regexp );
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(0);
        if ( RETVAL == NULL ) {
	  croak("Compilation of regexp failed");
	}
    OUTPUT:
	RETVAL

int
matches(self, pvalue)
        xmlRegexpPtr self
	SV* pvalue
    PREINIT:
        xmlChar * value = Sv2C(pvalue, NULL);
    CODE:
        if ( value == NULL )
	   XSRETURN_UNDEF;
	RETVAL = xmlRegexpExec(self,value);
        xmlFree( value );
    OUTPUT:
        RETVAL

int
isDeterministic(self)
        xmlRegexpPtr self
    CODE:
	RETVAL = xmlRegexpIsDeterminist(self);
    OUTPUT:
        RETVAL

void
DESTROY( self )
        xmlRegexpPtr self
    CODE:
        xs_warn( "DESTROY REGEXP OBJECT" );
   	xmlRegFreeRegexp(self);

#endif /* LIBXML_REGEXP_ENABLED */


MODULE = XML::LibXML       PACKAGE = XML::LibXML::XPathExpression

xmlXPathCompExprPtr
new(CLASS, pxpath)
        SV * pxpath
    PREINIT:
        xmlChar * xpath = Sv2C(pxpath, NULL);
        PREINIT_SAVED_ERROR
    CODE:
        if ( pxpath == NULL )
	   XSRETURN_UNDEF;
	INIT_ERROR_HANDLER;
	RETVAL = xmlXPathCompile( xpath );
        xmlFree( xpath );
        CLEANUP_ERROR_HANDLER;
        REPORT_ERROR(0);
        if ( RETVAL == NULL ) {
	  croak("Compilation of XPath expression failed!");
	}
    OUTPUT:
	RETVAL

void
DESTROY( self )
        xmlXPathCompExprPtr self
    CODE:
        xs_warn( "DESTROY COMPILED XPATH OBJECT" );
        xmlXPathFreeCompExpr(self);

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Common

PROTOTYPES: DISABLE

SV*
encodeToUTF8( encoding, string )
        const char * encoding
        SV * string
    PREINIT:
        xmlChar * realstring = NULL;
        xmlChar * tstr = NULL;
        xmlCharEncoding enc = 0;
        STRLEN len = 0;
        xmlBufferPtr in = NULL, out = NULL;
        xmlCharEncodingHandlerPtr coder = NULL;
	PREINIT_SAVED_ERROR
    CODE:
        if (!SvOK(string)) {
            XSRETURN_UNDEF;
        } else if (!SvCUR(string)) {
            XSRETURN_PV("");
        }
        realstring = (xmlChar*) SvPV(string, len);
        if ( realstring != NULL ) {
            /* warn("encode %s", realstring ); */
#ifdef HAVE_UTF8
            if ( !DO_UTF8(string) && encoding != NULL ) {
#else
            if ( encoding != NULL ) {
#endif
                enc = xmlParseCharEncoding( encoding );

                if ( enc == 0 ) {
                    /* this happens if the encoding is "" or NULL */
                    enc = XML_CHAR_ENCODING_UTF8;
                }

                if ( enc == XML_CHAR_ENCODING_UTF8 ) {
                    /* copy the string */
                    /* warn( "simply copy the string" ); */
                    tstr = xmlStrndup( realstring, len );
                }
                else {
                    INIT_ERROR_HANDLER;
                    if ( enc > 1 ) {
                        coder= xmlGetCharEncodingHandler( enc );
                    }
                    else if ( enc == XML_CHAR_ENCODING_ERROR ){
                        coder =xmlFindCharEncodingHandler( encoding );
                    }
                    else {
                        croak("no encoder found\n");
                    }
                    if ( coder == NULL ) {
                        croak( "cannot encode string" );
                    }
                    in    = xmlBufferCreateStatic((void*)realstring, len );
                    out   = xmlBufferCreate();
                    if ( xmlCharEncInFunc( coder, out, in ) >= 0 ) {
                        tstr = xmlStrdup( out->content );
                    }

                    xmlBufferFree( in );
                    xmlBufferFree( out );
                    xmlCharEncCloseFunc( coder );

                    CLEANUP_ERROR_HANDLER;
                    REPORT_ERROR(0);
                }
            }
            else {
                tstr = xmlStrndup( realstring, len );
            }

            if ( !tstr ) {
                croak( "return value missing!" );
            }

            len = xmlStrlen( tstr );
            RETVAL = newSVpvn( (const char *)tstr, len );
#ifdef HAVE_UTF8
            SvUTF8_on(RETVAL);
#endif
            xmlFree(tstr);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
decodeFromUTF8( encoding, string )
        const char * encoding
        SV* string
    PREINIT:
        xmlChar * tstr = NULL;
        xmlChar * realstring = NULL;
        xmlCharEncoding enc = 0;
        STRLEN len = 0;
        xmlBufferPtr in = NULL, out = NULL;
        xmlCharEncodingHandlerPtr coder = NULL;
	PREINIT_SAVED_ERROR
    CODE:
#ifdef HAVE_UTF8
        if ( !SvOK(string) ) {
            XSRETURN_UNDEF;
        } else if (!SvCUR(string)) {
            XSRETURN_PV("");
        } else if ( !SvUTF8(string) ) {
            croak("string is not utf8!!");
        } else {
#endif
            realstring = (xmlChar*) SvPV(string, len);
            if ( realstring != NULL ) {
                /* warn("decode %s", realstring ); */
                enc = xmlParseCharEncoding( encoding );
                if ( enc == 0 ) {
                    /* this happens if the encoding is "" or NULL */
                    enc = XML_CHAR_ENCODING_UTF8;
                }

                if ( enc == XML_CHAR_ENCODING_UTF8 ) {
                    /* copy the string */
                    /* warn( "simply copy the string" ); */
                    tstr = xmlStrdup( realstring );
                    len = xmlStrlen( tstr );
                }
                else {
                    INIT_ERROR_HANDLER;
                    if ( enc > 1 ) {
                        coder= xmlGetCharEncodingHandler( enc );
                    }
                    else if ( enc == XML_CHAR_ENCODING_ERROR ){
                        coder = xmlFindCharEncodingHandler( encoding );
                    }
                    else {
                        croak("no encoder found\n");
                    }

                    if ( coder == NULL ) {
                        croak( "cannot encode string" );
                    }

                    in    = xmlBufferCreate();
                    out   = xmlBufferCreate();
                    xmlBufferCCat( in, (char*) realstring );
                    if ( xmlCharEncOutFunc( coder, out, in ) >= 0 ) {
                        len  = xmlBufferLength( out );
                        tstr = xmlCharStrndup( (char*) xmlBufferContent( out ), len );
                    }

                    xmlBufferFree( in );
                    xmlBufferFree( out );
                    xmlCharEncCloseFunc( coder );
                    CLEANUP_ERROR_HANDLER;
                    REPORT_ERROR(0);
                    if ( !tstr ) {
                        croak( "return value missing!" );
                    }
                }

                RETVAL = newSVpvn( (const char *)tstr, len );
                xmlFree( tstr );
#ifdef HAVE_UTF8
                if ( enc == XML_CHAR_ENCODING_UTF8 ) {
                    SvUTF8_on(RETVAL);
                }
#endif
            }
            else {
                XSRETURN_UNDEF;
            }
#ifdef HAVE_UTF8
        }
#endif
    OUTPUT:
        RETVAL
