/* $Id$ */

#ifdef __cplusplus
extern "C" {
#endif

/* perl stuff */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* libxml2 stuff */
#include <libxml/xmlmemory.h>
#include <libxml/parser.h>
#include <libxml/parserInternals.h>
#include <libxml/HTMLparser.h>
#include <libxml/HTMLtree.h>
#include <libxml/tree.h>
#include <libxml/xpath.h>
#include <libxml/xmlIO.h>
/* #include <libxml/debugXML.h> */
#include <libxml/xmlerror.h>
#include <libxml/xinclude.h>
#include <libxml/valid.h>

/* XML::LibXML stuff */
#include "perl-libxml-mm.h"

#include "dom.h"
#include "xpath.h"

#ifdef __cplusplus
}
#endif

#ifdef VMS
extern int xmlDoValidityCheckingDefaultVal;
#define xmlDoValidityCheckingDefaultValue xmlDoValidityCheckingDefaultVal
extern int xmlSubstituteEntitiesDefaultVal;
#define xmlSubstituteEntitiesDefaultValue xmlSubstituteEntitiesDefaultVal
#else
extern int xmlDoValidityCheckingDefaultValue;
extern int xmlSubstituteEntitiesDefaultValue;
#endif
extern int xmlGetWarningsDefaultValue;
extern int xmlKeepBlanksDefaultValue;
extern int xmlLoadExtDtdDefaultValue;
extern int xmlPedanticParserDefaultValue;

#define SET_CB(cb, fld) \
    RETVAL = cb ? newSVsv(cb) : &PL_sv_undef;\
    if (SvOK(fld)) {\
        if (cb) {\
            if (cb != fld) {\
                sv_setsv(cb, fld);\
            }\
        }\
        else {\
            cb = newSVsv(fld);\
        }\
    }\
    else {\
        if (cb) {\
            SvREFCNT_dec(cb);\
            cb = NULL;\
        }\
    }

#define TEST_PERL_FLAG(flag) \
    SvTRUE(perl_get_sv(flag, FALSE)) ? 1 : 0


static SV * LibXML_match_cb = NULL;
static SV * LibXML_read_cb = NULL;
static SV * LibXML_open_cb = NULL;
static SV * LibXML_close_cb = NULL;
static SV * LibXML_error = NULL;

/* this should keep the default */
static xmlExternalEntityLoader LibXML_old_ext_ent_loader = NULL;

xmlParserInputPtr
LibXML_load_external_entity(
        const char * URL, 
        const char * ID, 
        xmlParserCtxtPtr ctxt)
{
    SV * self;
    HV * real_obj;
    SV ** func;
    int count;
    SV * results;
    STRLEN results_len;
    const char * results_pv;
    xmlParserInputBufferPtr input_buf;
    
    if (ctxt->_private == NULL) {
        return xmlNewInputFromFile(ctxt, URL);
    }
    
    if (URL == NULL) {
        URL = "";
    }
    if (ID == NULL) {
        ID = "";
    }
    
    self = (SV *)ctxt->_private;
    real_obj = (HV *)SvRV(self);
    func = hv_fetch(real_obj, "ext_ent_handler", 15, 0);
    
    if (func) {
        dSP;
        
        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;
        XPUSHs(sv_2mortal(newSVpv((char*)URL, 0)));
        XPUSHs(sv_2mortal(newSVpv((char*)ID, 0)));
        PUTBACK;
        
        count = perl_call_sv(*func, G_SCALAR);
        
        SPAGAIN;
        
        if (!count) {
            croak("external entity handler did not return a value");
        }
        
        results = POPs;
        
        results_pv = SvPV(results, results_len);
        input_buf = xmlParserInputBufferCreateMem(
                        results_pv,
                        results_len,
                        XML_CHAR_ENCODING_NONE
                        );
        
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

int 
LibXML_input_match(char const * filename)
{
    int results = 0;
    SV * global_cb;
    SV * callback = NULL;

    if (LibXML_match_cb && SvTRUE(LibXML_match_cb)) {
        callback = LibXML_match_cb;
    }
    else if ((global_cb = perl_get_sv("XML::LibXML::match_cb", FALSE))
             && SvTRUE(global_cb)) {
        callback = global_cb;
    }

    if (callback) {
        int count;
        SV * res;

        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 1);
        PUSHs(sv_2mortal(newSVpv((char*)filename, 0)));
        PUTBACK;

        count = perl_call_sv(callback, G_SCALAR);

        SPAGAIN;
        
        if (count != 1) {
            croak("match callback must return a single value");
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
    SV * global_cb;
    SV * callback = NULL;

    if (LibXML_open_cb && SvTRUE(LibXML_open_cb)) {
        callback = LibXML_open_cb;
    }
    else if ((global_cb = perl_get_sv("XML::LibXML::open_cb", FALSE))
            && SvTRUE(global_cb)) {
        callback = global_cb;
    }

    if (callback) {
        int count;

        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 1);
        PUSHs(sv_2mortal(newSVpv((char*)filename, 0)));
        PUTBACK;

        count = perl_call_sv(callback, G_SCALAR);

        SPAGAIN;
        
        if (count != 1) {
            croak("open callback must return a single value");
        }

        results = POPs;

        SvREFCNT_inc(results);

        PUTBACK;
        FREETMPS;
        LEAVE;
    }
    
    return (void *)results;
}

int 
LibXML_input_read(void * context, char * buffer, int len)
{
    SV * results = NULL;
    STRLEN res_len = 0;
    const char * output;
    SV * global_cb;
    SV * callback = NULL;
    SV * ctxt = (SV *)context;

    if (LibXML_read_cb && SvTRUE(LibXML_read_cb)) {
        callback = LibXML_read_cb;
    }
    else if ((global_cb = perl_get_sv("XML::LibXML::read_cb", FALSE))
            && SvTRUE(global_cb)) {
        callback = global_cb;
    }
    
    if (callback) {
        int count;

        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 2);
        PUSHs(ctxt);
        PUSHs(sv_2mortal(newSViv(len)));
        PUTBACK;

        count = perl_call_sv(callback, G_SCALAR);

        SPAGAIN;
        
        if (count != 1) {
            croak("read callback must return a single value");
        }

        output = POPp;
        if (output != NULL) {
            res_len = strlen(output);
            if (res_len) {
                strncpy(buffer, output, res_len);
            }
            else {
                buffer[0] = 0;
            }
        }
        
        FREETMPS;
        LEAVE;
    }
    
    /* warn("read, asked for: %d, returning: [%d] %s\n", len, res_len, buffer); */
    return res_len;
}

void 
LibXML_input_close(void * context)
{
    SV * global_cb;
    SV * callback = NULL;
    SV * ctxt = (SV *)context;

    if (LibXML_close_cb && SvTRUE(LibXML_close_cb)) {
        callback = LibXML_close_cb;
    }
    else if ((global_cb = perl_get_sv("XML::LibXML::close_cb", FALSE))
            && SvTRUE(global_cb)) {
        callback = global_cb;
    }

    if (callback) {
        int count;

        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 1);
        PUSHs(ctxt);
        PUTBACK;

        count = perl_call_sv(callback, G_SCALAR);

        SPAGAIN;

        SvREFCNT_dec(ctxt);
        
        if (!count) {
            croak("close callback failed");
        }

        PUTBACK;
        FREETMPS;
        LEAVE;
    }
}

void
LibXML_error_handler(void * ctxt, const char * msg, ...)
{
    va_list args;
    SV * sv;
    
    sv = NEWSV(0,512);
    
    va_start(args, msg);
    sv_vsetpvfn(sv, msg, strlen(msg), &args, NULL, 0, NULL);
    va_end(args);
    
    if (LibXML_error != NULL) {
        sv_catsv(LibXML_error, sv); /* remember the last error */
    }
    else {
        croak(SvPV(sv, PL_na));
    }
    SvREFCNT_dec(sv);
}

void
LibXML_validity_error(void * ctxt, const char * msg, ...)
{
    va_list args;
    SV * sv;
    
    sv = NEWSV(0,512);
    
    va_start(args, msg);
    sv_vsetpvfn(sv, msg, strlen(msg), &args, NULL, 0, NULL);
    va_end(args);
    
    if (LibXML_error != NULL) {
        sv_catsv(LibXML_error, sv); /* remember the last error */
    }
    else {
        croak(SvPV(sv, PL_na));
    }
    SvREFCNT_dec(sv);
}

void
LibXML_validity_warning(void * ctxt, const char * msg, ...)
{
    va_list args;
    STRLEN len;
    SV * sv;
    
    sv = NEWSV(0,512);
    
    va_start(args, msg);
    sv_vsetpvfn(sv, msg, strlen(msg), &args, NULL, 0, NULL);
    va_end(args);
    
    warn(SvPV(sv, len));
    SvREFCNT_dec(sv);
}

int
LibXML_read_perl (SV * ioref, char * buffer, int len)
{
    dSP;
    
    int cnt;
    SV * read_results;
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
        cnt = perl_call_method("read", G_SCALAR);
    }
    else {
        cnt = perl_call_pv("__read", G_SCALAR);
    }
    
    SPAGAIN;
    
    if (cnt != 1) {
        croak("read method call failed");
    }
    
    read_results = POPs;
    
    if (!SvOK(read_results)) {
        croak("read error");
    }
    
    read_length = SvIV(read_results);
    
    chars = SvPV(tbuff, read_length);
    strncpy(buffer, chars, read_length);
    
    FREETMPS;
    LEAVE;
    
    return read_length;
}

xmlDocPtr
LibXML_parse_stream(SV * self, SV * ioref, char * directory)
{
    xmlDocPtr doc = NULL;
    xmlParserCtxtPtr ctxt;
    int well_formed = 0;
    int valid = 0;
    char buffer[1024];
    int read_length;
    int ret = -1;
    char current_dir[512];
    
    if (directory == NULL) {
        if (getcwd(current_dir, 512) != 0) {
            directory = current_dir;
        }
        else {
            warn("couldn't get current directory: %s\n", strerror(errno));
        }
    }
    
    read_length = LibXML_read_perl(ioref, buffer, 4);
    if (read_length > 0) {
        ctxt = xmlCreatePushParserCtxt(NULL, NULL, buffer, read_length, NULL);
        if (ctxt == NULL) {
            croak("Could not create push parser context: %s", strerror(errno));
        }
        ctxt->directory = directory;
        ctxt->_private = (void*)self;
        while(read_length = LibXML_read_perl(ioref, buffer, 1024)) {
            xmlParseChunk(ctxt, buffer, read_length, 0);
        }
        ret = xmlParseChunk(ctxt, buffer, 0, 1);

        ctxt->directory = NULL;

        /* jsut being paranoid */
        if ( ret == 0 ) {
            doc = ctxt->myDoc;
            well_formed = ctxt->wellFormed;
            xmlFreeParserCtxt(ctxt);
        }
    }
    else {
        croak( "Empty Stream" );
    }
    
    if (!well_formed || (xmlDoValidityCheckingDefaultValue && !valid && (doc->intSubset || doc->extSubset) )) {
        xmlFreeDoc(doc);
        return NULL;
    }
    /* this should be done by libxml2 !? */
    if (doc->encoding == NULL) {
        doc->encoding = xmlStrdup((const xmlChar*)"utf-8");
    }

    if ( directory == NULL ) {
        STRLEN len;
        SV * newURI = sv_2mortal(newSVpvf("unknown-%12.12d", (void*)doc));
        doc->URL = xmlStrdup((const xmlChar*)SvPV(newURI, len));
    } else {
        doc->URL = xmlStrdup((const xmlChar*)directory);
    }
    
    return doc;
}

xmlDocPtr
LibXML_parse_html_stream(SV * self, SV * ioref)
{
    xmlDocPtr doc = NULL;
    htmlParserCtxtPtr ctxt;
    int well_formed = 0;
    char buffer[1024];
    int read_length;
    int ret = -1;
    
    read_length = LibXML_read_perl(ioref, buffer, 4);
    if (read_length > 0) {
        ctxt = htmlCreatePushParserCtxt(NULL, NULL, buffer, read_length, NULL, XML_CHAR_ENCODING_NONE);
        if (ctxt == NULL) {
            croak("Could not create html push parser context: %s", strerror(errno));
        }
        ctxt->_private = (void*)self;

        while(read_length = LibXML_read_perl(ioref, buffer, 1024)) {
            ret = htmlParseChunk(ctxt, buffer, read_length, 0);
            if ( ret != 0 ) {
                break;
            }   
        }
        ret = htmlParseChunk(ctxt, buffer, 0, 1);

        if ( ret == 0 ) {
            doc = ctxt->myDoc;
            well_formed = ctxt->wellFormed;
            htmlFreeParserCtxt(ctxt);
        }
    }
    else {
        croak( "Empty Stream" );
    }
    
    if (!well_formed) {
        xmlFreeDoc(doc);
        return NULL;
    }
    
    return doc;
}

void
LibXML_cleanup_parser() {
    xmlSubstituteEntitiesDefaultValue = 1;
    xmlKeepBlanksDefaultValue = 1;
    xmlGetWarningsDefaultValue = 0;
    xmlLoadExtDtdDefaultValue = 5;
    xmlPedanticParserDefaultValue = 0;
    xmlDoValidityCheckingDefaultValue = 0;
    xmlSetGenericErrorFunc(NULL, NULL);
}

void
LibXML_init_parser( SV * self ) {
    /* we fetch all switches and callbacks from the hash */

    xmlSetGenericErrorFunc(PerlIO_stderr(), 
                           (xmlGenericErrorFunc)LibXML_error_handler);

    if ( self != NULL ) {
        /* first fetch the values from the hash */
        HV* real_obj = (HV *)SvRV(self);
        SV** item    = NULL;
        SV * RETVAL  = NULL; /* dummy for the stupid macro */

        item = hv_fetch( real_obj, "XML_LIBXML_VALIDATION", 21, 0 );
        xmlDoValidityCheckingDefaultValue = item != NULL && SvTRUE(*item) ? 1 : 0;

        item = hv_fetch( real_obj, "XML_LIBXML_EXPAND_ENTITIES", 26, 0 );
        xmlSubstituteEntitiesDefaultValue = item != NULL && SvTRUE(*item) ? 1 : 0;

        item = hv_fetch( real_obj, "XML_LIBXML_KEEP_BLANKS", 22, 0 );
        xmlKeepBlanksDefaultValue = item != NULL && SvTRUE(*item) ? 1 : 0;
        item = hv_fetch( real_obj, "XML_LIBXML_PEDANTIC", 19, 0 );
        xmlPedanticParserDefaultValue = item != NULL && SvTRUE(*item) ? 1 : 0;

        item = hv_fetch( real_obj, "XML_LIBXML_EXT_DTD", 18, 0 );
        if ( item != NULL && SvTRUE(*item) )
            xmlLoadExtDtdDefaultValue |= 1;
        else
            xmlLoadExtDtdDefaultValue ^= 1;

        item = hv_fetch( real_obj, "XML_LIBXML_COMPLETE_ATTR", 24, 0 );
        if (item != NULL && SvTRUE(*item))
            xmlLoadExtDtdDefaultValue |= XML_COMPLETE_ATTRS;
        else
            xmlLoadExtDtdDefaultValue ^= XML_COMPLETE_ATTRS;
        /* now fetch the callbacks */

        item = hv_fetch( real_obj, "XML_LIBXML_READ_CB", 18, 0 );
        if ( item != NULL && SvTRUE(*item))
            LibXML_read_cb= *item;

        item = hv_fetch( real_obj, "XML_LIBXML_MATCH_CB", 19, 0 );
        if ( item != NULL  && SvTRUE(*item)) 
            LibXML_match_cb= *item;

        item = hv_fetch( real_obj, "XML_LIBXML_OPEN_CB", 18, 0 );
        if ( item != NULL  && SvTRUE(*item)) 
            LibXML_open_cb = *item;

        item = hv_fetch( real_obj, "XML_LIBXML_CLOSE_CB", 19, 0 );
        if ( item != NULL  && SvTRUE(*item)) 
            LibXML_close_cb = *item;

    }

    return;
/*    LibXML_old_ext_ent_loader =  xmlGetExternalEntityLoader(); */
/*    warn("      init parser callbacks!\n"); */

    xmlRegisterInputCallbacks((xmlInputMatchCallback) LibXML_input_match,
                              (xmlInputOpenCallback) LibXML_input_open,
                              (xmlInputReadCallback) LibXML_input_read,
                              (xmlInputCloseCallback) LibXML_input_close);

    xmlSetExternalEntityLoader( (xmlExternalEntityLoader)LibXML_load_external_entity );

}

void
LibXML_cleanup_callbacks() {
    
    return; 
/*   warn("      cleanup parser callbacks!\n"); */

    xmlCleanupInputCallbacks();
    xmlRegisterDefaultInputCallbacks();
/*    if ( LibXML_old_ext_ent_loader != NULL ) { */
        /* xmlSetExternalEntityLoader( NULL ); */
/*        xmlSetExternalEntityLoader( LibXML_old_ext_ent_loader ); */
/*        LibXML_old_ext_ent_loader = NULL; */
/*    } */

/*    xsltSetGenericDebugFunc(NULL, NULL); */

}

MODULE = XML::LibXML         PACKAGE = XML::LibXML

PROTOTYPES: DISABLE

BOOT:
    LIBXML_TEST_VERSION
    xmlInitParser();
    xmlRegisterInputCallbacks((xmlInputMatchCallback) LibXML_input_match,
                              (xmlInputOpenCallback) LibXML_input_open,
                              (xmlInputReadCallback) LibXML_input_read,
                              (xmlInputCloseCallback) LibXML_input_close);
    xmlSetGenericErrorFunc( NULL , 
                           (xmlGenericErrorFunc)LibXML_error_handler);
    xmlDoValidityCheckingDefaultValue = 0;
    xmlSubstituteEntitiesDefaultValue = 1;
    xmlGetWarningsDefaultValue = 0;
    xmlKeepBlanksDefaultValue = 1;
    xmlLoadExtDtdDefaultValue = 5;
    xmlPedanticParserDefaultValue = 0;

void
END()
    CODE:
        xmlCleanupParser();


int
XML_ELEMENT_NODE()
    ALIAS: 
        XML::LibXML::ELEMENT_NODE = 1
    CODE:
        RETVAL = 1;
    OUTPUT:
        RETVAL
        
int
XML_ATTRIBUTE_NODE()
    ALIAS: 
        XML::LibXML::ATTRIBUTE_NODE = 1
    CODE:
        RETVAL = 2;
    OUTPUT:
        RETVAL


int
XML_TEXT_NODE()
    ALIAS: 
        XML::LibXML::TEXT_NODE = 1
    CODE:
        RETVAL = 3;
    OUTPUT:
        RETVAL

int
XML_CDATA_SECTION_NODE()
    ALIAS: 
        XML::LibXML::CDATA_SECTION_NODE = 1
    CODE:
        RETVAL = 4;
    OUTPUT:
        RETVAL

int
XML_ENTITY_REF_NODE()
    ALIAS: 
        XML::LibXML::ENTITY_REFERENCE_NODE = 1
    CODE:
        RETVAL = 5;
    OUTPUT:
        RETVAL

int
XML_ENTITY_NODE()
    ALIAS: 
        XML::LibXML::ENTITY_NODE = 1
    CODE:
        RETVAL = 6;
    OUTPUT:
        RETVAL

int
XML_PI_NODE()
    ALIAS: 
        XML::LibXML::PROCESSING_INSTRUCTION_NODE = 1
    CODE:
        RETVAL = 7;
    OUTPUT:
        RETVAL

int
XML_COMMENT_NODE()
    ALIAS: 
        XML::LibXML::COMMENT_NODE = 1
    CODE:
        RETVAL = 8;
    OUTPUT:
        RETVAL

int
XML_DOCUMENT_NODE()
    ALIAS: 
        XML::LibXML::DOCUMENT_NODE = 1
    CODE:
        RETVAL = 9;
    OUTPUT:
        RETVAL

int
XML_DOCUMENT_TYPE_NODE()
    ALIAS: 
        XML::LibXML::DOCUMENT_TYPE_NODE = 1
    CODE:
        RETVAL = 10;
    OUTPUT:
        RETVAL

int
XML_DOCUMENT_FRAG_NODE()
    ALIAS: 
        XML::LibXML::DOCUMENT_FRAGMENT_NODE = 1
    CODE:
        RETVAL = 11;
    OUTPUT:
        RETVAL

int
XML_NOTATION_NODE()
    ALIAS: 
        XML::LibXML::NOTATION_NODE = 1
    CODE:
        RETVAL = 12;
    OUTPUT:
        RETVAL

int
XML_HTML_DOCUMENT_NODE()
    ALIAS: 
        XML::LibXML::HTML_DOCUMENT_NODE = 1
    CODE:
        RETVAL = 13;
    OUTPUT:
        RETVAL

int
XML_DTD_NODE()
    ALIAS:
        XML::LibXML::DTD_NODE = 1
    CODE:
        RETVAL = 14;
    OUTPUT:
        RETVAL

int
XML_ELEMENT_DECL()
    ALIAS: 
        XML::LibXML::ELEMENT_DECLARATION = 1
    CODE:
        RETVAL = 15;
    OUTPUT:
        RETVAL

int
XML_ATTRIBUTE_DECL()
    ALIAS: 
        XML::LibXML::ATTRIBUTE_DECLARATION = 1
    CODE:
        RETVAL = 16;
    OUTPUT:
        RETVAL

int
XML_ENTITY_DECL()
    ALIAS: 
        XML::LibXML::ENTITY_DECLARATION = 1
    CODE:
        RETVAL = 17;
    OUTPUT:
        RETVAL

int
XML_NAMESPACE_DECL()
    ALIAS: 
        XML::LibXML::NAMESPACE_DECLARATION = 1
    CODE:
        RETVAL = 18;
    OUTPUT:
        RETVAL

int
XML_XINCLUDE_START()
    ALIAS: 
        XML::LibXML::XINCLUDE_START = 1
    CODE:
        RETVAL = 19;
    OUTPUT:
        RETVAL

int
XML_XINCLUDE_END()
    ALIAS: 
        XML::LibXML::XINCLUDE_END = 1
    CODE:
        RETVAL = 20;
    OUTPUT:
        RETVAL

char *
get_last_error(CLASS)
        char * CLASS 
    PREINIT: 
        STRLEN len;
    CODE:
        RETVAL = NULL;
        if (LibXML_error != NULL) {
            RETVAL = SvPV(LibXML_error, len);
        }
    OUTPUT:
        RETVAL


SV*
_parse_string(self, string, directory = NULL)
        SV * self
        SV * string
        char * directory
    PREINIT:
        xmlParserCtxtPtr ctxt;
        char * CLASS = "XML::LibXML::Document";
        STRLEN len;
        char * ptr;
        int well_formed;
        int valid;
        int ret;
        xmlDocPtr real_dom;
        ProxyObject * proxy;
        HV* real_obj = (HV *)SvRV(self);
        SV** item    = NULL;
    CODE:
        ptr = SvPV(string, len);
        if (len == 0) {
            croak("Empty string");
        }

        ctxt = xmlCreateMemoryParserCtxt(ptr, len);
        if (ctxt == NULL) {
            croak("Couldn't create memory parser context: %s", strerror(errno));
        }
        ctxt->directory = directory;

        # warn( "context created\n");

        ctxt->_private = (void*)self;
        
        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);
        
        # warn( "context initialized \n");        
        LibXML_init_parser(self);
        ret = xmlParseDocument(ctxt);

        # warn( "document parsed \n");

        ctxt->directory = NULL;

        well_formed = ctxt->wellFormed;
        valid = ctxt->valid;

        real_dom = ctxt->myDoc;
        xmlFreeParserCtxt(ctxt);

        sv_2mortal(LibXML_error);
        
        if ( directory == NULL ) {
            STRLEN len;
            SV * newURI = sv_2mortal(newSVpvf("unknown-%12.12d", (void*)real_dom));
            real_dom->URL = xmlStrdup((const xmlChar*)SvPV(newURI, len));
        } else {
            real_dom->URL = xmlStrdup((const xmlChar*)directory);
        }

        if (!well_formed || (xmlDoValidityCheckingDefaultValue && !valid && (real_dom->intSubset || real_dom->extSubset) )) {
            xmlFreeDoc(real_dom);
            RETVAL = &PL_sv_undef;    
            croak(SvPV(LibXML_error, len));
        }
        else {
            STRLEN n_a;
            # ok check the xincludes
            item = hv_fetch( real_obj, "XML_LIBXML_EXPAND_XINCLUDE", 26, 0 );
            if ( item != NULL && SvTRUE(*item) ) {
                # warn( "xinclude\n" );
                xmlXIncludeProcess(real_dom);
            }

            RETVAL = nodeToSv((xmlNodePtr)real_dom);
            setSvNodeExtra(RETVAL,RETVAL);
        }        
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser(); 
    OUTPUT:
        RETVAL

SV*
_parse_fh(self, fh, directory = NULL)
        SV * self
        SV * fh
        char * directory
    PREINIT:
        char * CLASS = "XML::LibXML::Document";
        STRLEN len;
        xmlDocPtr real_dom;
        ProxyObject* proxy;
    CODE:
        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);

        LibXML_init_parser(self);
        real_dom = LibXML_parse_stream(self, fh, directory);
        
        sv_2mortal(LibXML_error);
        
        if (real_dom == NULL) {
            RETVAL = &PL_sv_undef;    
            croak(SvPV(LibXML_error, len));
        }
        else {
            STRLEN n_a;
            HV* real_self = (HV*)SvRV(self);
            SV** item;
            # ok check the xincludes
            item = hv_fetch( real_self, "XML_LIBXML_EXPAND_XINCLUDE", 26, 0 );
            if ( item != NULL && SvTRUE(*item) ) 
                xmlXIncludeProcess(real_dom);

            RETVAL = nodeToSv((xmlNodePtr)real_dom);
            setSvNodeExtra(RETVAL,RETVAL);
        }
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();
    OUTPUT:
        RETVAL
        
SV*
_parse_file(self, filename)
        SV * self
        const char * filename
    PREINIT:
        xmlParserCtxtPtr ctxt;
        char * CLASS = "XML::LibXML::Document";
        int well_formed = 0;
        int valid = 0;
        STRLEN len;
        xmlDocPtr real_dom = NULL;
        ProxyObject * proxy = NULL;
    CODE:
        LibXML_init_parser(self);
        ctxt = xmlCreateFileParserCtxt(filename);

        if (ctxt == NULL) {
            croak("Could not create file parser context for file '%s' : %s", filename, strerror(errno));
        }
        ctxt->_private = (void*)self;
        
        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);

        xmlParseDocument(ctxt);

        well_formed = ctxt->wellFormed;
        valid = ctxt->valid;

        real_dom = ctxt->myDoc;
        xmlFreeParserCtxt(ctxt);
        
        sv_2mortal(LibXML_error);
        
        if (!well_formed || (xmlDoValidityCheckingDefaultValue && !valid && (real_dom->intSubset || real_dom->extSubset) )) {
            xmlFreeDoc(real_dom);
            RETVAL = &PL_sv_undef ;  
            croak(SvPV(LibXML_error, len));
        }
        else {
            HV* real_self = (HV*)SvRV(self);
            SV** item = NULL;

            # ok check the xincludes
            item = hv_fetch( real_self, "XML_LIBXML_EXPAND_XINCLUDE", 26, 0 );
            if ( item != NULL && SvTRUE(*item) )  {
                # warn( "xincludes\n" );
                xmlXIncludeProcess(real_dom);
            }

            RETVAL = nodeToSv((xmlNodePtr)real_dom);
            setSvNodeExtra(RETVAL,RETVAL);
        }
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();
    OUTPUT:
        RETVAL

SV*
parse_html_string(self, string)
        SV * self
        SV * string
    PREINIT:
        htmlParserCtxtPtr ctxt;
        char * CLASS = "XML::LibXML::Document";
        STRLEN len;
        char * ptr;
        int well_formed;
        int ret;
        xmlDocPtr real_dom;
        ProxyObject * proxy;
    CODE:
        ptr = SvPV(string, len);
        if (len == 0) {
            croak("Empty string");
        }
        
        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);
        
        LibXML_init_parser(self);
        real_dom = htmlParseDoc((xmlChar*)ptr, NULL);
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();        

        sv_2mortal(LibXML_error);
        
        if (!real_dom || ((*SvPV(LibXML_error, len)) != '\0')) {
            RETVAL = &PL_sv_undef;    
            croak(SvPV(LibXML_error, len));
        }
        else {
            STRLEN n_a;
            SV * newURI = newSVpvf("unknown-%12.12d", real_dom);
            real_dom->URL = xmlStrdup((const xmlChar*)SvPV(newURI, n_a));
            SvREFCNT_dec(newURI);
            RETVAL = nodeToSv((xmlNodePtr)real_dom);
            setSvNodeExtra(RETVAL,RETVAL);
        }
    OUTPUT:
        RETVAL

SV*
parse_html_fh(self, fh)
        SV * self
        SV * fh
    PREINIT:
        char * CLASS = "XML::LibXML::Document";
        STRLEN len;
        xmlDocPtr real_dom;
    CODE:
        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);
        
        LibXML_init_parser(self);
        real_dom = LibXML_parse_html_stream(self, fh);
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();
        
        sv_2mortal(LibXML_error);
        
        if (!real_dom || ((*SvPV(LibXML_error, len)) != '\0')) {
            RETVAL = &PL_sv_undef;    
            croak(SvPV(LibXML_error, len));
        }
        else {
            STRLEN n_a;
            SV * newURI = newSVpvf("unknown-%12.12d", real_dom);
            real_dom->URL = xmlStrdup((const xmlChar*)SvPV(newURI, n_a));
            SvREFCNT_dec(newURI);
            RETVAL = nodeToSv((xmlNodePtr)real_dom);
            setSvNodeExtra(RETVAL,RETVAL);
        }
    OUTPUT:
        RETVAL
        
SV*
parse_html_file(self, filename)
        SV * self
        const char * filename
    PREINIT:
        char * CLASS = "XML::LibXML::Document";
        STRLEN len;
        xmlDocPtr real_dom;
        ProxyObject * proxy;
    CODE:
        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);
        
        LibXML_init_parser(self);
        real_dom = htmlParseFile((char*)filename, NULL);
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();

        sv_2mortal(LibXML_error);
        
        if (!real_dom) {
            RETVAL = &PL_sv_undef ;  
            croak(SvPV(LibXML_error, len));
        }
        else {
            RETVAL = nodeToSv( (xmlNodePtr)real_dom ); 
            setSvNodeExtra(RETVAL,RETVAL);
        }
    OUTPUT:
        RETVAL

SV*
_parse_xml_chunk( self, svchunk, encoding="UTF-8" )
        SV * self
        SV * svchunk
        char * encoding
    PREINIT:
        char * CLASS = "XML::LibXML::DocumentFragment";
        xmlChar *chunk;
        xmlNodePtr rv = NULL;
        xmlNodePtr fragment= NULL;
        ProxyObject *ret=NULL;
        xmlNodePtr rv_end = NULL;
        char * ptr;
        STRLEN len;
    CODE:
        if ( encoding == NULL ) encoding = "UTF-8";
        ptr = SvPV(svchunk, len);
        if (len == 0) {
            croak("Empty string");
        }

        /* encode the chunk to UTF8 */
        chunk = Sv2C(svchunk, (const xmlChar*)encoding);

        if ( chunk != NULL ) {
            LibXML_error = sv_2mortal(newSVpv("", 0));
            LibXML_init_parser(self);
            rv = domReadWellBalancedString( NULL, chunk );
            LibXML_cleanup_callbacks();
            LibXML_cleanup_parser();    

            if ( rv != NULL ) {
                /* now we append the nodelist to a document
                   fragment which is unbound to a Document!!!! */
                # warn( "good chunk, create fragment" );

                /* step 1: create the fragment */
                fragment = xmlNewDocFragment( NULL );
                RETVAL = nodeToSv(fragment);
                setSvNodeExtra(RETVAL,RETVAL);

                /* step 2: set the node list to the fragment */
                fragment->children = rv;
                rv->parent = fragment;
                rv_end = rv;
                while ( rv_end != NULL ) {
                    fragment->last = rv_end;
                    rv_end->parent = fragment;
                    rv_end = rv_end->next;
                }
            }
            else {
                # warn( "bad chunk" );
                XSRETURN_UNDEF;
            }
            /* free the chunk we created */
            xmlFree( chunk );
        }
    OUTPUT:
        RETVAL

void
processXIncludes( self, dom )
        SV * self
        SV * dom
    PREINIT:
        xmlDocPtr real_dom = (xmlDocPtr)((ProxyObject*)SvIV((SV*)SvRV(dom)))->object;
    CODE:
        # first init the stuff for the parser
        LibXML_init_parser(self);
        xmlXIncludeProcess(real_dom);        
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();

SV*
encodeToUTF8( encoding, string )
        const char * encoding
        SV * string
    PREINIT:
        xmlChar * realstring;
        xmlChar * tstr;
    CODE:
        xs_warn( "encoding start" );
        realstring = Sv2C(string,(xmlChar*) encoding);
        if ( realstring != NULL ) {
            RETVAL = C2Sv(realstring, NULL);
            xmlFree( realstring );
#ifdef HAVE_UTF8
            SvUTF8_on(RETVAL);
#endif
        }
        else {
            XSRETURN_UNDEF;
        }
        xs_warn( "encoding done" );
    OUTPUT:
        RETVAL

SV*
decodeFromUTF8( encoding, string ) 
        const char * encoding
        SV* string
    PREINIT:
        xmlChar * tstr;
        xmlChar * realstring;
    CODE: 
        xs_warn( "decoding start" );
#ifdef HAVE_UTF8
        if ( SvUTF8(string) ) {
#endif
            realstring = Sv2C(string,(const xmlChar*)"UTF8" );
            if ( realstring != NULL ) {
                tstr =  (xmlChar*)domDecodeString( (const char*)encoding,
                                                   (const xmlChar*)realstring );
                if ( tstr != NULL ) {
                    RETVAL = C2Sv((const xmlChar*)tstr,(const xmlChar*)encoding);
                    xmlFree( tstr );
                }
                else {
                    XSRETURN_UNDEF;
                }
                xmlFree( realstring ); 
            }
            else {
                XSRETURN_UNDEF;
            }
#ifdef HAVE_UTF8
        }
        else {
            XSRETURN_UNDEF;
        }
#endif
        xs_warn( "decoding done" );
    OUTPUT:
        RETVAL


MODULE = XML::LibXML         PACKAGE = XML::LibXML::Document

void
DESTROY(self)
        ProxyObject* self
    CODE:
        if ( self->object != NULL ) {
            if ( self->extra != NULL && SvREFCNT( self->extra ) > 1 ) {
                SvREFCNT_dec( self->extra );
#                warn( "TWO Document nodes" );
            } else {
                xmlFreeDoc((xmlDocPtr)self->object);
#                warn( "REAL DOCUMENT DROP SUCCEEDS" );
            }
        }        
        self->object = NULL;
        Safefree( self );

SV *
toString(self, format=0)
        ProxyObject* self
        int format
    PREINIT:
        xmlDocPtr real_dom;
        xmlChar *result=NULL;
        int len=0;
    CODE:
        real_dom = (xmlDocPtr)self->object;
        if ( format <= 0 ) {
            # warn( "use no formated toString!" );
            xmlDocDumpMemory(real_dom, &result, &len);
        }
        else {
            int t_indent_var = xmlIndentTreeOutput;
            # warn( "use formated toString!" );
            xmlIndentTreeOutput = 1;
            xmlDocDumpFormatMemory( real_dom, &result, &len, format ); 
            xmlIndentTreeOutput = t_indent_var;
        }

    	if (result == NULL) {
	        # warn("Failed to convert doc to string");           
            RETVAL = &PL_sv_undef;
    	} else {
            # warn("%s, %d\n",result, len);
            RETVAL = newSVpvn((char *)result, (STRLEN)len);
            xmlFree(result);
#ifdef HAVE_UTF8
            xs_warn( "use utf8" );
            SvUTF8_on(RETVAL);
#endif
        }
    OUTPUT:
        RETVAL

SV *
toStringHTML(self)
        ProxyObject* self
    PREINIT:
        xmlDocPtr real_dom;
        xmlChar *result=NULL;
        int len=0;
    CODE:
        real_dom = (xmlDocPtr)self->object;
        # warn( "use no formated toString!" );
        htmlDocDumpMemory(real_dom, &result, &len);

    	if (result == NULL) {
	    # warn("Failed to convert doc to string");           
            RETVAL = &PL_sv_undef;
    	} else {
            # warn("%s, %d\n",result, len);
            RETVAL = newSVpvn((char *)result, (STRLEN)len);
            xmlFree(result);
        }
    OUTPUT:
        RETVAL

int
is_valid(self, ...)
        xmlDocPtr self
    PREINIT:
        xmlValidCtxt cvp;
        ProxyObject * dtd_proxy;
        xmlDtdPtr dtd;
        SV * dtd_sv;
    CODE:
        LibXML_error = sv_2mortal(newSVpv("", 0));
        cvp.userData = (void*)PerlIO_stderr();
        cvp.error = (xmlValidityErrorFunc)LibXML_validity_error;
        cvp.warning = (xmlValidityWarningFunc)LibXML_validity_warning;
        if (items > 1) {
            dtd_sv = ST(1);
            if ( sv_isobject(dtd_sv) && (SvTYPE(SvRV(dtd_sv)) == SVt_PVMG) ) {
                dtd_proxy = (ProxyObject*)SvIV((SV*)SvRV( dtd_sv ));
                if (dtd_proxy != NULL) {
                    dtd = (xmlDtdPtr)dtd_proxy->object;
                }
            }
            else {
                croak("is_valid: argument must be a DTD object");
            }
            RETVAL = xmlValidateDtd(&cvp, self, dtd);
        }
        else {
            RETVAL = xmlValidateDocument(&cvp, self);
        }
    OUTPUT:
        RETVAL

int
validate(self, ...)
        xmlDocPtr self
    PREINIT:
        xmlValidCtxt cvp;
        ProxyObject * dtd_proxy;
        xmlDtdPtr dtd;
        SV * dtd_sv;
        STRLEN n_a;
    CODE:
        LibXML_error = sv_2mortal(newSVpv("", 0));
        cvp.userData = (void*)PerlIO_stderr();
        cvp.error = (xmlValidityErrorFunc)LibXML_validity_error;
        cvp.warning = (xmlValidityWarningFunc)LibXML_validity_warning;
        if (items > 1) {
            dtd_sv = ST(1);
            if ( sv_isobject(dtd_sv) && (SvTYPE(SvRV(dtd_sv)) == SVt_PVMG) ) {
                dtd_proxy = (ProxyObject*)SvIV((SV*)SvRV( dtd_sv ));
                if (dtd_proxy != NULL) {
                    dtd = (xmlDtdPtr)dtd_proxy->object;
                }
            }
            else {
                croak("is_valid: argument must be a DTD object");
            }
            RETVAL = xmlValidateDtd(&cvp, self , dtd);
        }
        else {
            RETVAL = xmlValidateDocument(&cvp, self);
        }
        if (RETVAL == 0) {
            croak(SvPV(LibXML_error, n_a));
        }
    OUTPUT:
        RETVAL
        

void
process_xinclude(self)
        SV* self
    PREINIT:
        ProxyObject* real_self = (ProxyObject*)SvIV((SV*)SvRV(self));
    CODE:
        LibXML_init_parser( NULL );
        xmlXIncludeProcess((xmlDocPtr)real_self->object);
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();

const char *
URI (doc, new_URI=NULL)
        xmlDocPtr doc
        char * new_URI
    CODE:
        RETVAL = xmlStrdup(doc->URL );
        if (new_URI) {
            xmlFree( (xmlChar*) doc->URL);
            doc->URL = xmlStrdup((xmlChar*)new_URI);
        }
    OUTPUT:
        RETVAL

SV*
createDocument( CLASS, version="1.0", encoding=0 )
        char * CLASS
        char * version 
        char * encoding
    ALIAS:
        XML::LibXML::Document::new = 1
    PREINIT:
        xmlDocPtr real_dom=NULL;
        ProxyObject * ret= NULL;
    CODE:
        real_dom = domCreateDocument( version, encoding ); 
        RETVAL = nodeToSv((xmlNodePtr)real_dom);
        setSvNodeExtra(RETVAL,RETVAL);
    OUTPUT:
        RETVAL

SV*
createDocumentFragment( dom )
        SV * dom
    PREINIT:
        SV * frag_sv = NULL;
        xmlDocPtr real_dom;
        xmlNodePtr fragment= NULL;
    CODE:
        real_dom = (xmlDocPtr)getSvNode(dom);
        RETVAL = nodeToSv(xmlNewDocFragment( real_dom ));
        setSvNodeExtra(RETVAL, RETVAL);
    OUTPUT:
        RETVAL

SV*
createElement( dom, name )
        SV * dom
        SV* name
    PREINIT:
        xmlNodePtr docfrag,newNode;
        xmlDocPtr real_dom;
        xmlChar * elname = NULL;
        SV * docfrag_sv = NULL;
    CODE:
        real_dom = (xmlDocPtr)getSvNode(dom);
        docfrag = xmlNewDocFragment( real_dom );
        docfrag_sv = nodeToSv(docfrag);
        setSvNodeExtra(docfrag_sv, docfrag_sv);

        elname = nodeSv2C( name , (xmlNodePtr) real_dom );

        newNode = xmlNewNode(NULL , elname);
        xmlFree(elname);
        
        newNode->doc = real_dom;
        domAppendChild( docfrag, newNode );
        # warn( newNode->name );
        RETVAL = nodeToSv(newNode);
        setSvNodeExtra(RETVAL,docfrag_sv);
    OUTPUT:
        RETVAL

SV*
createElementNS( dom, nsURI, qname)
         SV * dom
         char *nsURI
         SV* qname 
     PREINIT:
         xmlNodePtr newNode;
         xmlChar *prefix;
         xmlChar* quali_name;
         xmlChar *lname = NULL;
         xmlNsPtr ns = NULL;
         xmlDocPtr real_dom;
         xmlNodePtr docfrag = NULL;
         xmlChar * encstring = NULL;
         SV * docfrag_sv = NULL;
     CODE:
        real_dom = (xmlDocPtr)getSvNode(dom);

        quali_name = nodeSv2C( qname , (xmlNodePtr) real_dom );

        docfrag = xmlNewDocFragment( real_dom );
        docfrag_sv = nodeToSv(docfrag);
        setSvNodeExtra(docfrag_sv, docfrag_sv);

        if ( nsURI != NULL && strlen(nsURI)!=0 ){
            lname = xmlSplitQName2(quali_name, &prefix);
            ns = domNewNs (0 , prefix, nsURI );
        }
        else {
            lname = quali_name;
        }

        newNode = xmlNewNode( ns , lname );

        newNode->doc = real_dom;
        domAppendChild( docfrag, newNode );
        RETVAL = nodeToSv(newNode);
        setSvNodeExtra(RETVAL,docfrag_sv);
        xmlFree(quali_name);
     OUTPUT:
        RETVAL

SV *
createTextNode( dom, content )
        SV * dom
        SV * content
    PREINIT:
        xmlNodePtr newNode;
        xmlDocPtr real_dom;
        xmlNodePtr docfrag = NULL;
        xmlChar * encstring = NULL;
        SV * docfrag_sv = NULL;
    CODE:
        real_dom = (xmlDocPtr)getSvNode(dom);
 
        docfrag = xmlNewDocFragment( real_dom );
        docfrag_sv =nodeToSv(docfrag);
        encstring = nodeSv2C( content , (xmlNodePtr) real_dom );

        newNode = xmlNewDocText( real_dom, encstring );
        xmlFree(encstring);
        newNode->doc = real_dom;

        domAppendChild( docfrag, newNode );

        RETVAL = nodeToSv(newNode);
        setSvNodeExtra(RETVAL,docfrag_sv);
    OUTPUT:
        RETVAL

SV *
createComment( dom , content )
        SV * dom
        SV * content
    PREINIT:
        xmlNodePtr newNode;
        xmlDocPtr real_dom;
        xmlNodePtr docfrag = NULL;
        SV * docfrag_sv = NULL;
        char * encstring = NULL;
    CODE:
        real_dom = (xmlDocPtr)getSvNode(dom);

        docfrag = xmlNewDocFragment( real_dom );
        docfrag_sv =nodeToSv(docfrag);
        encstring = nodeSv2C( content , (xmlNodePtr) real_dom );
        newNode = xmlNewDocComment( real_dom, encstring );
        xmlFree( encstring );
        newNode->doc = real_dom;
        domAppendChild( docfrag, newNode );

        RETVAL = nodeToSv(newNode);
        setSvNodeExtra(RETVAL,docfrag_sv);
    OUTPUT:
        RETVAL

SV *
createCDATASection( dom, content )
        SV * dom
        SV * content
    PREINIT:
        xmlNodePtr newNode;
        xmlDocPtr real_dom;
        xmlNodePtr docfrag = NULL;
        SV * docfrag_sv = NULL;
        xmlChar * encstring = NULL;
    CODE:
        real_dom = (xmlDocPtr)getSvNode(dom);
 
        docfrag = xmlNewDocFragment( real_dom );
        docfrag_sv =nodeToSv(docfrag);
        encstring = nodeSv2C( content , (xmlNodePtr) real_dom );
        newNode = domCreateCDATASection( real_dom, encstring );
        xmlFree(encstring);
        newNode->doc = real_dom;
        domAppendChild( docfrag, newNode );

        RETVAL = nodeToSv(newNode);
        setSvNodeExtra(RETVAL,docfrag_sv);
    OUTPUT:
        RETVAL

SV *
createAttribute( dom, name , value=&PL_sv_undef )
        SV * dom
        SV * name
        SV * value
    PREINIT:
        xmlNodePtr newNode;
        xmlDocPtr real_dom;
        xmlChar *encname = NULL;
        xmlChar *encval  = NULL;
    CODE:
        real_dom = (xmlDocPtr)getSvNode(dom);  
        encname = nodeSv2C( name , (xmlNodePtr) real_dom );
        encval  = nodeSv2C( value , (xmlNodePtr) real_dom );

        newNode = (xmlNodePtr)xmlNewProp(NULL, encname , encval );
        xmlFree(encname);
        xmlFree(encval);

        newNode->doc = real_dom;
        if ( newNode->children!=NULL ) {
            newNode->doc = real_dom;
        }
        RETVAL = nodeToSv(newNode);
        setSvNodeExtra(RETVAL,dom);  
    OUTPUT:
        RETVAL

SV *
createAttributeNS( dom, nsURI, qname, value=&PL_sv_undef )
        SV * dom
        char * nsURI
        SV * qname
        SV * value
    PREINIT:
        xmlNodePtr newNode;
        xmlChar *prefix;
        xmlChar *lname =NULL;
        xmlChar *encname =NULL;
        xmlChar *encval =NULL;
        xmlNsPtr ns=NULL;
        xmlDocPtr real_dom;
    CODE:
        real_dom = (xmlDocPtr)getSvNode(dom);
        encname = nodeSv2C( qname , (xmlNodePtr) real_dom );
        if ( nsURI != NULL && strlen( nsURI ) != 0 ){
            lname = xmlSplitQName2(encname, &prefix);
            ns = domNewNs (0 , prefix , (xmlChar*)nsURI);
        }
        else{
            lname = encname;
        }

        encval = nodeSv2C( value , (xmlNodePtr) real_dom );

        if ( ns != NULL ) {
            newNode = (xmlNodePtr) xmlNewNsProp(NULL, ns, lname , encval );
        }
        else {
            newNode = (xmlNodePtr) xmlNewProp( NULL, lname, encval );
        }
        
        xmlFree(lname);
        xmlFree(encname);
        xmlFree(encval);

        newNode->doc = real_dom;

        if ( newNode->children!=NULL ) {
            newNode->children->doc = real_dom;
        }
        RETVAL = nodeToSv(newNode);
        setSvNodeExtra(RETVAL,dom);  
    OUTPUT:
        RETVAL

void 
setDocumentElement( dom , proxy )
        SV * dom
        SV * proxy
    PREINIT:
        xmlDocPtr real_dom;
        xmlNodePtr elem;
        SV* oldsv =NULL;
    CODE:
        real_dom = (xmlDocPtr)getSvNode(dom);
        elem = getSvNode(proxy);

        /* please correct me if i am wrong: the document element HAS to be
         * an ELEMENT NODE
         */ 
        if ( elem->type == XML_ELEMENT_NODE ) {
            domSetDocumentElement( real_dom, elem );
            fix_proxy_extra(proxy, dom);            
        }

SV *
getDocumentElement( dom )
        SV * dom
    ALIAS:
        XML::LibXML::Document::documentElement = 1
    PREINIT:
        xmlNodePtr elem;
        xmlDocPtr real_dom;
    CODE:
        real_dom = (xmlDocPtr)getSvNode(dom);
        elem = domDocumentElement( real_dom ) ;
        if ( elem ) {
            RETVAL = nodeToSv(elem);
            setSvNodeExtra(RETVAL,dom);  
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

void
insertProcessingInstruction( dom, name, content )
        SV * dom
        SV * name 
        SV * content
    ALIAS:
        insertPI = 1
    PREINIT:
        xmlNodePtr pinode = NULL;
        xmlDocPtr real_dom;
        xmlChar * enctarg;
        xmlChar * encdata;
    CODE:
        real_dom = (xmlDocPtr)getSvNode(dom);
        enctarg = nodeSv2C( name , (xmlNodePtr) real_dom );
        encdata = nodeSv2C( content , (xmlNodePtr) real_dom );
        pinode = xmlNewPI( enctarg, encdata );
        xmlFree(enctarg);
        xmlFree(encdata);
        domInsertBefore( (xmlNodePtr)real_dom, 
                         pinode, 
                         domDocumentElement( real_dom ) );

SV *
createProcessingInstruction( dom, name, content=&PL_sv_undef )
        SV * dom
        SV * name 
        SV * content
    ALIAS:
        createPI = 1
    PREINIT:
        xmlNodePtr newNode;
        xmlDocPtr real_dom;
        xmlNodePtr docfrag = NULL;
        xmlChar * enctarg;
        xmlChar * encdata;
        SV * docfrag_sv = NULL;
    CODE:
        real_dom = (xmlDocPtr)getSvNode(dom);
        docfrag = xmlNewDocFragment( real_dom );
        docfrag_sv = nodeToSv((xmlNodePtr)docfrag );

        enctarg = nodeSv2C( name , (xmlNodePtr) real_dom );
        encdata = nodeSv2C( content , (xmlNodePtr) real_dom );

        newNode = xmlNewPI( enctarg, encdata );
        xmlFree(enctarg);
        xmlFree(encdata);
        /* newNode = xmlNewPI( name, content ); */
        newNode->doc = real_dom;
        domAppendChild( docfrag, newNode );
        # warn( newNode->name );
        RETVAL = nodeToSv(newNode);
        setSvNodeExtra(RETVAL,docfrag_sv);        
    OUTPUT:
        RETVAL

SV *
importNode( dom, node, move=0 ) 
        SV * dom
        SV * node
        int move
    PREINIT:
        xmlNodePtr ret = NULL;
        xmlNodePtr real_node = NULL;
        xmlDocPtr real_dom;
    CODE:
        real_dom = (xmlDocPtr)getSvNode(dom);
        real_node= getSvNode(node);
        ret = domImportNode( real_dom, real_node, move );
        if ( ret ) {
            RETVAL = nodeToSv(ret);
            if ( move == 0 ){
                fix_proxy_extra(RETVAL, dom);
            }
            else {
                setSvNodeExtra(RETVAL, dom);
            } 
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

char*
getEncoding( self )
        SV* self
    CODE:
        if( self != NULL && self!=&PL_sv_undef) {
            RETVAL = xmlStrdup((xmlChar*)((xmlDocPtr)getSvNode(self))->encoding );
        }
    OUTPUT:
        RETVAL

void
setEncoding( self, encoding )
        SV* self
        char *encoding
    CODE:
        if( self != NULL && self!=&PL_sv_undef) {
            ((xmlDocPtr)getSvNode(self))->encoding = xmlStrdup( encoding );
        }

char*
getVersion( self ) 
         SV * self
    CODE:
        if( self != NULL && self != &PL_sv_undef ) {
            RETVAL = xmlStrdup( ((xmlDocPtr)getSvNode(self))->version );
        }
    OUTPUT:
        RETVAL

void
setVersion( self, version )
        SV* self
        char *version
    CODE:
        if( self != NULL && self!=&PL_sv_undef) {
            ((xmlDocPtr)getSvNode(self))->version = xmlStrdup( version );
        }


MODULE = XML::LibXML         PACKAGE = XML::LibXML::Dtd

SV *
new(CLASS, external, system)
        char * CLASS
        char * external
        char * system
    CODE:
        LibXML_error = sv_2mortal(newSVpv("", 0));
        RETVAL = nodeToSv((xmlNodePtr)xmlParseDTD((const xmlChar*)external, (const xmlChar*)system));
    OUTPUT:
        RETVAL

ProxyObject *
parse_string(CLASS, str, ...)
        char * CLASS
        char * str
    PREINIT:
        STRLEN n_a;
        xmlDtdPtr res;
        SV * encoding_sv;
        xmlParserInputBufferPtr buffer;
        xmlCharEncoding enc = XML_CHAR_ENCODING_NONE;
        char * new_string;
    CODE:
        LibXML_error = sv_2mortal(newSVpv("", 0));
        if (items > 2) {
            encoding_sv = ST(2);
            if (items > 3) {
                croak("parse_string: too many parameters");
            }
            /* warn("getting encoding...\n"); */
            enc = xmlParseCharEncoding(SvPV(encoding_sv, n_a));
            if (enc == XML_CHAR_ENCODING_ERROR) {
                croak("Parse of encoding %s failed: %s", SvPV(encoding_sv, n_a), SvPV(LibXML_error, n_a));
            }
        }
        /* warn("make buffer\n"); */
        buffer = xmlAllocParserInputBuffer(enc);
        /* xmlParserInputBufferCreateMem(str, strlen(str), enc); */
        new_string = xmlStrdup(str);
        xmlParserInputBufferPush(buffer, strlen(new_string), new_string);
        /* warn("parse\n"); */
        res = xmlIOParseDTD(NULL, buffer, enc);
        /* warn("free : 0x%x\n", buffer); */
        /* NOTE: For some reason freeing this InputBuffer causes a segfault! */
        /* xmlFreeParserInputBuffer(buffer); */
        /* warn("make proxy\n"); */
        if (res != NULL) {
            RETVAL = make_proxy_node((xmlNodePtr)res);
        }
        else {
            croak("couldn't parse DTD: %s", SvPV(LibXML_error, n_a));
        }
        /* warn("return\n"); */
    OUTPUT:
        RETVAL

void
DESTROY( node )
        ProxyObject * node
    PREINIT:
        xmlDtdPtr real_node;
    CODE:
        real_node = (xmlDtdPtr)node->object;
        if ( node->extra == NULL )
            xmlFreeDtd(real_node);

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Node

void
DESTROY( node )
        SV * node
    PREINIT:
        SV* dom;
        xmlNodePtr real_node;
    CODE:
        /* XXX should destroy node->extra if refcnt == 0 */
        if (node != NULL || node != &PL_sv_undef ) {
            real_node = getSvNode(node);
            dom = getSvNodeExtra(node);
            if ( dom != NULL && dom != &PL_sv_undef && real_node != NULL ) {
                if ( SvREFCNT(dom) > 0 ){
                    SvREFCNT_dec(dom);
                }
                free_proxy_node(node);
            }
        }


int 
getType( node ) 
        xmlNodePtr node
    ALIAS:
        XML::LibXML::Node::nodeType = 1
    CODE:
        RETVAL = node->type;
    OUTPUT:
        RETVAL

void
unbindNode( proxyelem )
        SV* proxyelem
    PREINIT:
        xmlNodePtr elem       = NULL;
        xmlNodePtr docfrag    = NULL;
        ProxyObject * dfProxy = NULL;
        SV * docfrag_sv       = NULL;
    CODE:
        elem = getSvNode(proxyelem);
        domUnbindNode( elem );

        docfrag = xmlNewDocFragment( elem->doc );
        docfrag_sv = nodeToSv( docfrag );
        setSvNodeExtra( docfrag_sv, docfrag_sv );
    
        domAppendChild( docfrag, elem );
        fix_proxy_extra( proxyelem, docfrag_sv );

SV*
removeChild( paren, child ) 
        xmlNodePtr paren
        SV* child
    PREINIT:
        SV* docfrag_sv;
        xmlNodePtr ret, docfrag;
    CODE:
        ret = domRemoveChild( paren, getSvNode(child) );
        if (ret != NULL) {
            RETVAL = newSVsv(child);
            docfrag = xmlNewDocFragment(paren->doc );
            docfrag_sv = nodeToSv(docfrag);
            setSvNodeExtra(docfrag_sv, docfrag_sv);
            fix_proxy_extra(RETVAL,docfrag_sv);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
replaceChild( paren, newChild, oldChild ) 
        SV* paren
        SV* newChild
        SV* oldChild
    PREINIT:
        SV* docfrag_sv;
        xmlNodePtr pNode, nNode, oNode, docfrag;
        xmlNodePtr ret;
    CODE:
        pNode = getSvNode( paren );
        nNode = getSvNode( newChild );
        oNode = getSvNode( oldChild );
        ret = domReplaceChild( pNode, nNode, oNode );
        if (ret != NULL) {
            /* create document fragment */
            docfrag = xmlNewDocFragment( pNode->doc );
            docfrag_sv = nodeToSv(docfrag);
            setSvNodeExtra(docfrag_sv, docfrag_sv);
        
            RETVAL = newSVsv(oldChild);

            fix_proxy_extra(RETVAL,docfrag_sv);
            fix_proxy_extra(newChild,getSvNodeExtra(paren));    
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

void
appendChild( parent, child )
        SV* parent
        SV* child
    PREINIT:
        ProxyObject* pproxy = NULL;
        ProxyObject* cproxy = NULL;
        xmlNodePtr test = NULL, pNode, cNode;
    CODE:
        pNode = getSvNode(parent);
        cNode = getSvNode(child);

        if ( pNode == NULL ) {
               croak("parent problem!\n");
        }
        if ( cNode == NULL ) {
               croak("child problem!\n");
        }

        if (pNode->type == XML_DOCUMENT_NODE
             && cNode->type == XML_ELEMENT_NODE ) {
            /* silently ignore */
            xs_warn( "use setDocumentElement!!!!\n" );
        }
        else {
            if ( domAppendChild( pNode, cNode ) != NULL ) {
                fix_proxy_extra( child, parent );
            }
            else {
                xs_warn("append problem ...\n");
            }
        }

SV*
cloneNode( self, deep ) 
        SV* self
        int deep
    PREINIT:
        xmlNodePtr ret;
        xmlNodePtr docfrag = NULL;
        SV * docfrag_sv = NULL;
        xmlNodePtr realself = getSvNode(self);
    CODE:
        ret = xmlCopyNode( realself, deep );
        if (ret != NULL) {
            docfrag = xmlNewDocFragment( ret->doc );
            docfrag_sv =nodeToSv(docfrag);
            domAppendChild( docfrag, ret );            
            
            RETVAL = nodeToSv(ret);
            fix_proxy_extra(RETVAL, docfrag_sv);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL


SV*
getParentNode( self )
        SV* self
    ALIAS:
        XML::LibXML::Node::parentNode = 1
    PREINIT:
        xmlNodePtr ret;
    CODE:
        ret = getSvNode(self)->parent;
        if (ret != NULL) {
            RETVAL = nodeToSv(ret);
            setSvNodeExtra(RETVAL, getSvNodeExtra(self));
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

int 
hasChildNodes( elem )
        xmlNodePtr elem
    CODE:
        RETVAL = elem->children == 0 ? 0 : 1 ;
    OUTPUT:
        RETVAL

SV*
getNextSibling( elem )
        SV* elem
    ALIAS:
        XML::LibXML::Node::nextSibling = 1
    PREINIT:
        xmlNodePtr ret;
    CODE:
        ret = getSvNode(elem)->next ;
        if ( ret != NULL ) {
            RETVAL = nodeToSv(ret);
            setSvNodeExtra(RETVAL, getSvNodeExtra(elem));
        }	
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
getPreviousSibling( elem )
        SV * elem
    ALIAS:
        XML::LibXML::Node::previousSibling = 1
    PREINIT:
        xmlNodePtr ret;
    CODE:
        ret = getSvNode(elem)->prev;
        if ( ret != NULL ) {
            RETVAL = nodeToSv(ret);
            setSvNodeExtra(RETVAL, getSvNodeExtra(elem));
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
getFirstChild( elem )
        SV* elem
    ALIAS:
        XML::LibXML::Node::firstChild = 1
    PREINIT:
        xmlNodePtr ret;
    CODE:
        ret = getSvNode(elem)->children;
        if ( ret != NULL ) {
            RETVAL = nodeToSv(ret);
            setSvNodeExtra(RETVAL, getSvNodeExtra(elem));
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL


SV*
getLastChild( elem )
        SV* elem
    ALIAS:
        XML::LibXML::Node::lastChild = 1
    PREINIT:
        xmlNodePtr ret;
    CODE:
        ret = getSvNode(elem)->last;
        if ( ret != NULL ) {
            RETVAL = nodeToSv(ret);
            setSvNodeExtra(RETVAL, getSvNodeExtra(elem));
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL


void
insertBefore( self, new, ref ) 
        SV* self
        SV* new
        SV* ref
    PREINIT:
        xmlNodePtr pNode, nNode, oNode;
    CODE:
        pNode = getSvNode(self);
        nNode = getSvNode(new);
        oNode = getSvNode(ref);

        if ( !(pNode->type == XML_DOCUMENT_NODE
             && nNode->type == XML_ELEMENT_NODE ) 
             && domInsertBefore( pNode, nNode, oNode ) != NULL ) {
            fix_proxy_extra(new,getSvNodeExtra(self));
        }


void
insertAfter( self, new, ref )
        SV* self
        SV* new
        SV* ref
    PREINIT:
        xmlNodePtr pNode, nNode, oNode;
    CODE:
        pNode = getSvNode(self);
        nNode = getSvNode(new);
        oNode = getSvNode(ref);

        if ( !(pNode->type == XML_DOCUMENT_NODE
             && nNode->type == XML_ELEMENT_NODE ) 
             && domInsertAfter( pNode, nNode, oNode ) != NULL ) {
            fix_proxy_extra(new,getSvNodeExtra(self));
        }

SV*
getOwnerDocument( elem )
        SV* elem
    ALIAS:
        XML::LibXML::Node::ownerDocument = 1
    PREINIT:
        xmlNodePtr self = getSvNode(elem);
    CODE:
        if( self != NULL
            && self->doc != NULL
            && getSvNodeExtra(elem) != NULL ){
            RETVAL = getSvNodeExtra(elem);
            SvREFCNT_inc( RETVAL );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
getOwner( elem ) 
        SV* elem
    CODE:
        if( getSvNodeExtra(elem) != NULL ){
            RETVAL = getSvNodeExtra(elem);
            SvREFCNT_inc( RETVAL );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

void
setOwnerDocument( elem, doc )
        SV* elem
        SV* doc
    PREINIT:
        xmlDocPtr real_doc;
    CODE:
        /* no increase here, because owner document is may not the root! */
        real_doc = (xmlDocPtr)getSvNode(doc);
        domSetOwnerDocument( getSvNode(elem), real_doc );

SV*
getName( node )
        xmlNodePtr node
    ALIAS:
        XML::LibXML::Node::nodeName = 1
        XML::LibXML::Attr::name     = 2
    PREINIT:
        char * name;
    CODE:
        if( node != NULL ) {
            name =  domName( node );
            RETVAL = C2Sv(name,NULL);
            xmlFree( name );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

void
setName( node , value )
        xmlNodePtr node
        SV* value
    PREINIT:
        xmlChar* string;
    CODE:
        string = nodeSv2C( value , node );
        domSetName( node, string );
        xmlFree(string);

SV*
getData( proxy_node, useDomEncoding = &PL_sv_undef ) 
        SV * proxy_node 
        SV * useDomEncoding
    ALIAS:
        XML::LibXML::Attr::value     = 1
        XML::LibXML::Node::nodeValue = 2
        XML::LibXML::Attr::getValue  = 3
    PREINIT:
        xmlNodePtr node;
        xmlChar * content = NULL;
    CODE:
        /* this implementation is prolly b0rked!
         * I have to go through the spec to find out what should
         * be returned here.
         */
        xs_warn( "getDATA" );
        node = getSvNode(proxy_node); 

        if( node != NULL ) {
            if ( node->type != XML_ATTRIBUTE_NODE ){
                    if ( node->content != NULL ) {
                        content = xmlStrdup(node->content);
                    }
                    else {
                        if ( node->children != NULL ) {
                            xmlNodePtr cnode = node->children;
                            xs_warn ( "oh the node has children ..." );
                            /* ok then toString in this case ... */
                            while (cnode) {
                                xmlBufferPtr buffer = xmlBufferCreate();
                               /* buffer = xmlBufferCreate(); */
                                xmlNodeDump( buffer, node->doc, cnode, 0, 0 );
                                if ( buffer->content != NULL ) {
                                    xs_warn( "add item" );
                                    if ( content != NULL ) {
                                        content = xmlStrcat( content, buffer->content );
                                    }
                                    else {
                                        content = xmlStrdup( buffer->content );
                                    }
                                }
                                xmlBufferFree( buffer );
                                cnode = cnode->next;
                            }
                        }
                    }                    
             }
            else if ( node->children != NULL ) {
                xs_warn("copy kiddies content!");
                content = xmlStrdup(node->children->content);
            }
            else {
                xs_warn( "no bloddy data!" );
            }
        }

        if ( content != NULL ){
            xs_warn ( "content follows"); xs_warn( content );
            if ( SvTRUE(useDomEncoding) ) {
                RETVAL = nodeC2Sv(content, node);
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


void
_findnodes( node, xpath )
        SV* node
        char * xpath 
    PREINIT:
        xmlNodeSetPtr nodelist = NULL;
        SV * element = NULL ;
        int len = 0 ;
    PPCODE:
        nodelist = domXPathSelect( getSvNode(node), xpath );
        if ( nodelist && nodelist->nodeNr > 0 ) {
            int i = 0 ;
            const char * cls = "XML::LibXML::Node";
            xmlNodePtr tnode;
            
            len = nodelist->nodeNr;
            for( i ; i < len; i++){
               /* we have to create a new instance of an objectptr. and then 
                 * place the current node into the new object. afterwards we can 
                 * push the object to the array!
                 */
                element = NULL;
                tnode = nodelist->nodeTab[i];

                if (tnode->type == XML_NAMESPACE_DECL) {
                    element = sv_newmortal();
                    cls = domNodeTypeName( tnode );
                    element = sv_setref_pv( element, (char *)cls, (void*)tnode );
                } else {
                    element = nodeToSv(tnode);
                    setSvNodeExtra(element, getSvNodeExtra(node));
                }
                XPUSHs( element );
            }            
            xmlXPathFreeNodeSet( nodelist );
        }

void
_find ( node, xpath )
        SV* node
        char * xpath
    PREINIT:
        xmlXPathObjectPtr found = NULL;
        xmlNodeSetPtr nodelist = NULL;
        SV* element = NULL ;
        int len = 0 ;
    PPCODE:
        found = domXPathFind( getSvNode(node), xpath );
        if (found) {
            switch (found->type) {
                case XPATH_NODESET:
                    /* return as a NodeList */
                    /* access ->nodesetval */
                    XPUSHs(newSVpv("XML::LibXML::NodeList", 0));
                    nodelist = found->nodesetval;
                    if ( nodelist && nodelist->nodeNr > 0 ) {
                        int i = 0 ;
                        const char * cls = "XML::LibXML::Node";
                        xmlNodePtr tnode;
                        SV * element;
                        
                        len = nodelist->nodeNr;
                        for( i ; i < len; i++){
                            /* we have to create a new instance of an
                             * objectptr. and then
                             * place the current node into the new
                             * object. afterwards we can
                             * push the object to the array!
                             */

                            tnode = nodelist->nodeTab[i];
                            element = nodeToSv(tnode);
                            setSvNodeExtra(element,getSvNodeExtra(node));

                            XPUSHs( element );
                        }
                    }
                    break;
                case XPATH_BOOLEAN:
                    /* return as a Boolean */
                    /* access ->boolval */
                    XPUSHs(newSVpv("XML::LibXML::Boolean", 0));
                    XPUSHs(newSViv(found->boolval));
                    break;
                case XPATH_NUMBER:
                    /* return as a Number */
                    /* access ->floatval */
                    XPUSHs(newSVpv("XML::LibXML::Number", 0));
                    XPUSHs(newSVnv(found->floatval));
                    break;
                case XPATH_STRING:
                    /* access ->stringval */
                    /* return as a Literal */
                    XPUSHs(newSVpv("XML::LibXML::Literal", 0));
                    XPUSHs(newSVpv(found->stringval, 0));
                    break;
                default:
                    croak("Unknown XPath return type");
            }
            xmlXPathFreeObject(found);
        }

void
getChildnodes( node )
        SV* node
    ALIAS:
        XML::LibXML::Node::childNodes = 1
    PREINIT:
        xmlNodePtr cld;
        SV * element;
        int len = 0;
        int wantarray = GIMME_V;
    PPCODE:
        cld = getSvNode(node)->children;
        xs_warn("childnodes start");
        while ( cld ) {
            if( wantarray != G_SCALAR ) {
                xs_warn("   --");
                xs_warn(domNodeTypeName(cld));
	            element = nodeToSv(cld);
                if( cld->type == XML_PI_NODE ) {
                    xs_warn("pi found!!!!");
                }
                setSvNodeExtra(element, getSvNodeExtra(node));
                xs_warn("   +-");
                XPUSHs( element );
            }
            xs_warn("   -+");
            cld = cld->next;
            len++;
        }
        xs_warn("childnodes start");
        if ( wantarray == G_SCALAR ) {
            XPUSHs( newSViv(len) );
        }

SV*
toString( self, useDomEncoding = &PL_sv_undef )
        xmlNodePtr self
        SV * useDomEncoding
    PREINIT:
        xmlBufferPtr buffer;
        char *ret = NULL;
    CODE:
        buffer = xmlBufferCreate();
        xmlNodeDump( buffer, self->doc, self, 0, 0 );
        if ( buffer->content != 0 ) {
            ret= xmlStrdup( buffer->content );
        }
        xmlBufferFree( buffer );

        if ( ret != NULL ) {
            if ( SvTRUE(useDomEncoding) ) {
                RETVAL = nodeC2Sv(ret, self) ;
            }
            else {
                RETVAL = C2Sv(ret, NULL) ;
            }
            xmlFree( ret );
        }
        else {
	        # warn("Failed to convert doc to string");           
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

int 
isEqual( self, other )
        xmlNodePtr self
        xmlNodePtr other
    ALIAS:
        XML::LibXML::Node::isSameNode = 1
    CODE:
        RETVAL = 0;
        if( self == other ) {
            RETVAL = 1;
        }
    OUTPUT:
        RETVAL

int
getPointer( self )
        xmlNodePtr self
    CODE:
        RETVAL = (int)self;
    OUTPUT:
        RETVAL

SV*
getLocalName( node )
        xmlNodePtr node
    ALIAS:
        XML::LibXML::Node::localname = 1
    PREINIT:
        char * lname;
    CODE:
        if( node != NULL ) {
            lname = xmlStrdup( node->name );
            RETVAL = C2Sv(lname,NULL);
            xmlFree( lname );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
getPrefix( node )
        xmlNodePtr node
    ALIAS:
        XML::LibXML::Node::prefix = 1
    PREINIT:
        xmlChar * prefix;
    CODE:
        if( node != NULL 
            && node->ns != NULL
            && node->ns->prefix != NULL ) {            
            prefix = xmlStrdup(node->ns->prefix);
            RETVAL = C2Sv(prefix, NULL);
            xmlFree(prefix);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
getNamespaceURI( node )
        xmlNodePtr node
    PREINIT:
        xmlChar * nsURI;
    CODE:
        if( node != NULL
            && node->ns != NULL
            && node->ns->href != NULL ) {
            nsURI =  xmlStrdup(node->ns->href);
            RETVAL = C2Sv(nsURI,NULL);
            xmlFree(nsURI);
        }
        else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

int 
hasAttributes( node ) 
        SV* node
    PREINIT:
        xmlNodePtr self = getSvNode(node);
    CODE:
        RETVAL = 0;
        if( self->type == 1 
            ||self->type == 7
            ||self->type >= 9 ) {

            if( self->properties != NULL ) {
                RETVAL = 1;
            }
        }
    OUTPUT:
        RETVAL

void
getAttributes( node )
        SV* node
    ALIAS:
        XML::LibXML::Node::attributes = 1
    PREINIT:
        xmlAttrPtr attr = NULL;
        xmlNodePtr real_node = NULL;
        xmlNsPtr ns = NULL;
        SV * element;
        int len=0;
        const char * CLASS = "XML::LibXML::Attr";
        int wantarray = GIMME_V;
    PPCODE:
        real_node = getSvNode(node);

        attr      = real_node->properties;
        while ( attr != NULL ) {
            if ( wantarray != G_SCALAR ) {
                element = nodeToSv((xmlNodePtr)attr);
                setSvNodeExtra(element,getSvNodeExtra(node));
                XPUSHs(element);
            }
            attr = attr->next;
            len++;
        }
        ns = real_node->nsDef;
        while ( ns != NULL ) {
            const char * CLASS = "XML::LibXML::Namespace";
            if ( wantarray != G_SCALAR ) {
                /* hmm this namespace handling looks odd ... */
                element = sv_newmortal();
                XPUSHs( sv_setref_pv( element, (char *)CLASS, (void*)ns ) );
            }
            ns = ns->next;
            len++;
        }
        if( wantarray == G_SCALAR ) {
            XPUSHs( newSViv( len ) );
        }

void
getAttributesNS( node,nsURI )
        SV* node
        char * nsURI
    PREINIT:
        xmlAttrPtr attr = NULL;
        xmlNodePtr real_node = NULL;
        SV * element;
        int len = 0;
        const char * CLASS = "XML::LibXML::Attr";
        int wantarray = GIMME_V;
    PPCODE:
        real_node = (xmlNodePtr)getSvNode(node);

        attr      = real_node->properties;
        while ( attr != NULL ) {
            if( attr->ns != NULL && xmlStrcmp( nsURI, attr->ns->href ) == 0 ){ 
                if( wantarray != G_SCALAR ) {
                    element = nodeToSv((xmlNodePtr)attr);
                    setSvNodeExtra(element,getSvNodeExtra(node));
                    XPUSHs( element );
                }
                len++;
            }
            attr = attr->next;
        }
        if( wantarray == G_SCALAR ) {
            XPUSHs( newSViv( len ) );
        }

void
getNamespaces ( node )
        xmlNodePtr node
    ALIAS:
        XML::LibXML::Node::namespaces = 1
    PREINIT:
        xmlNsPtr ns = NULL;
        int len=0;
        const char * CLASS = "XML::LibXML::Namespace";
        int wantarray = GIMME_V;
        SV * element;
    PPCODE:
        ns = node->nsDef;
        while ( ns != NULL ) {
            if ( wantarray != G_SCALAR ) {
                element = sv_newmortal();
                XPUSHs( sv_setref_pv( element, (char *)CLASS, (void*)ns ) );
            }
            ns = ns->next;
            len++;
        }
        if( wantarray == G_SCALAR ) {
            XPUSHs( newSViv( len ) );
        }

void
getNamespace ( node, perlprefix )
        xmlNodePtr node
        SV * perlprefix
    PREINIT:
        xmlDocPtr real_dom= NULL;
        xmlChar *prefix;
        xmlNsPtr ns = NULL;
        const char * CLASS = "XML::LibXML::Namespace";
        SV * element;
    PPCODE:
        if ( node != NULL && perlprefix != NULL && perlprefix != &PL_sv_undef ) {
            prefix = nodeSv2C( perlprefix, node );

            ns = node->nsDef;
            while ( ns != NULL ) {
                if (ns->prefix != NULL) {
                    if (xmlStrcmp(prefix, ns->prefix) == 0) {
                        element = sv_newmortal();
                        XPUSHs( sv_setref_pv( element, (char *)CLASS, (void*)ns ) );
                        break;
                    }
                } else {
                    if (xmlStrlen(prefix) == 0) {
                        element = sv_newmortal();
                        XPUSHs( sv_setref_pv( element, (char *)CLASS, (void*)ns ) );
                        break;
                    }
                }
                ns = ns->next;
            }
            xmlFree(prefix);
        }

SV*
string_value ( node, useDomEncoding = &PL_sv_undef )
        xmlNodePtr node
        SV * useDomEncoding
    ALIAS:
        to_literal = 1
    CODE:
        /* we can't just return a string, because of UTF8! */
        if ( SvTRUE(useDomEncoding) ) {
            RETVAL = nodeC2Sv(xmlXPathCastNodeToString(node), node);
        }
        else {
            RETVAL = C2Sv(xmlXPathCastNodeToString(node), NULL);
        }
    OUTPUT:
        RETVAL

double
to_number ( node )
        xmlNodePtr node
    CODE:
        RETVAL = xmlXPathCastNodeToNumber(node);
    OUTPUT:
        RETVAL

        
MODULE = XML::LibXML         PACKAGE = XML::LibXML::Element

SV*
new(CLASS, name )
        char * CLASS
        char * name
    PREINIT:
        xmlNodePtr newNode;
    CODE:
        newNode = xmlNewNode( 0, name );
        if( newNode != NULL ) {
            # init the keeping fragment
            xmlNodePtr docfrag = NULL;
            ProxyObject * dfProxy = NULL; 
            SV * docfrag_sv = NULL;

            docfrag = xmlNewDocFragment(NULL);
            docfrag_sv= nodeToSv(docfrag);
         
            newNode->next     = 0;
            newNode->prev     = 0;
            newNode->children = 0 ;
            newNode->last     = 0;
            newNode->doc      = 0;

            domAppendChild( docfrag, newNode );

            RETVAL = nodeToSv(newNode);
            fix_proxy_extra(RETVAL, docfrag_sv);
        }
    OUTPUT:
        RETVAL

void
setAttribute( perlelem, name, value )
        SV* perlelem	
        SV* name
        SV* value
    PREINIT:
        xmlNodePtr elem;
        xmlChar* xname; 
        xmlChar* xvalue;
    CODE:
        if ( elem = getSvNode(perlelem) ) {
            xname  = nodeSv2C( name , elem );
            xvalue = nodeSv2C( value , elem );
            
            xmlSetProp( elem, xname, xvalue );
            xmlFree( xname );
            xmlFree( xvalue );
        }

void
setAttributeNS( elem, nsURI, qname, value )
        xmlNodePtr elem
        char* nsURI
        SV* qname
        SV* value
    PREINIT:
        xmlDocPtr real_dom;
        xmlChar *xqname;
        xmlChar *xvalue;
        xmlChar *prefix = NULL;
        xmlChar *lname  = NULL;
        xmlNsPtr ns     = NULL;
    CODE:
        xqname  = nodeSv2C( qname , elem );
        xvalue  = nodeSv2C( value , elem );
 
        if ( nsURI != NULL && xmlStrlen(nsURI) != 0 ) {
            lname = xmlSplitQName2(xqname, &prefix);
        
            ns = domNewNs (elem , prefix , nsURI);
            xmlSetNsProp( elem, ns, lname, xvalue );
            xmlFree(lname);
            xmlFree(prefix);
        }
        else {
            xmlSetProp( elem, xqname, xvalue );
        }
        xmlFree( xqname );
        xmlFree( xvalue );

SV *
setAttributeNode( elem, attrnode ) 
        SV * elem
        SV * attrnode 
    CODE:
        /* this chunk is not 100% correct, sind the SV already exists.
         * the future version of nodeToSv should get the correct value!
         */
        if ( elem != NULL 
             && elem != &PL_sv_undef
             && attrnode != NULL
             && attrnode != &PL_sv_undef ) {
            RETVAL = nodeToSv( (xmlNodePtr)domSetAttributeNode( getSvNode(elem), (xmlAttrPtr)getSvNode(attrnode) ) );
            setSvNodeExtra(RETVAL, getSvNodeExtra(elem));
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

int 
hasAttribute( elem, pname ) 
        xmlNodePtr elem
        SV * pname
    PREINIT:
        xmlAttrPtr att = NULL;
        xmlChar *name = NULL;
        xmlDocPtr real_dom = NULL;
    CODE:
        if ( elem != NULL && pname != NULL && pname!=&PL_sv_undef ){
            name  = nodeSv2C( pname , elem );
        
            /**
             * xmlHasProp() returns the attribute node, which is not
             * exactly what we want as a boolean value 
             **/
 
            att = xmlHasProp( elem, name );
            xmlFree( name );
            RETVAL = att == NULL ? 0 : 1 ;
        }
        else {
            XSRETURN_UNDEF;
        }            
    OUTPUT:
        RETVAL

int 
hasAttributeNS( elem, nsURI, pname ) 
        xmlNodePtr elem
        char * nsURI
        SV * pname
    PREINIT:
        xmlChar *name = NULL;
        xmlDocPtr real_dom = NULL;
        xmlAttrPtr att = NULL;
    CODE:
        if ( elem != NULL && pname != NULL && pname!=&PL_sv_undef ){
            name  = nodeSv2C( pname , elem );
            /**
             * domHasNsProp() returns the attribute node, which is not
             * exactly what
             * we want as a boolean value 
             **/
            att = domHasNsProp( elem, name, nsURI );
            xmlFree(name);
            RETVAL = att == NULL ? 0 : 1 ;
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
getAttribute( elem, pname ) 
        SV * elem
        SV * pname 
    PREINIT:
        xmlNodePtr node;
        xmlChar * name;
	    xmlChar * content = NULL;
    CODE:
        node = getSvNode( elem );
        name = nodeSv2C( pname, node );
        content = xmlGetProp( node , name );
        if ( content != NULL ) {     
            RETVAL  = C2Sv(content, NULL );
            xmlFree( content );
        }
        else {
            XSRETURN_UNDEF;
        }
        xmlFree(name);
    OUTPUT:
        RETVAL

SV*
getAttributeNS( elem, nsURI ,pname ) 
        SV* elem
        char * nsURI
        SV * pname 
    PREINIT:
        xmlAttrPtr att;
        xmlNodePtr node;
        xmlChar * name;
	    xmlChar * content = NULL;
    CODE:
        node = getSvNode( elem );
        name = nodeSv2C( pname, node );
        att = domHasNsProp( node, name, nsURI );
        if ( att != NULL && att->children != NULL ) {
            content = xmlStrdup( att->children->content ); 
        }
        if ( content != NULL ) {
            RETVAL  = C2Sv(content,NULL);
            xmlFree( content );
        }
        else {
            XSRETURN_UNDEF;
        }
        xmlFree( name ); 
    OUTPUT:
        RETVAL


SV *
getAttributeNode( elemnode, pname )
        SV * elemnode
        SV * pname
    PREINIT:
        xmlChar* name;
        xmlDocPtr real_dom = NULL;
        xmlNodePtr elem;
        xmlAttrPtr attrnode = NULL;
    CODE:
        elem = getSvNode(elemnode);
        if ( elem != NULL ) {
            name  = nodeSv2C( pname , elem );
            attrnode = xmlHasProp( elem, name );
            if ( attrnode != NULL ) {
                RETVAL = nodeToSv((xmlNodePtr)attrnode);
                setSvNodeExtra(RETVAL,getSvNodeExtra(elemnode));
            }
            else {
                XSRETURN_UNDEF;
            }
            xmlFree(name);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV *
getAttributeNodeNS( elemobj, nsURI, pname )
        SV* elemobj 
        char * nsURI
        SV * pname
    PREINIT:
        xmlChar* name;
        xmlDocPtr real_dom = NULL;
        xmlNodePtr elem;
        xmlAttrPtr attrnode = NULL;
    CODE:
        elem = getSvNode(elemobj);
        if ( elem != NULL ) {
            name  = nodeSv2C( pname ,elem );

            attrnode = domHasNsProp( elem, name, nsURI );
            if ( attrnode != NULL ) {
                RETVAL = nodeToSv((xmlNodePtr)attrnode);
                setSvNodeExtra(RETVAL,getSvNodeExtra(elemobj));
            }
            else {
                XSRETURN_UNDEF;
            }
            xmlFree(name);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

void
removeAttribute( elem, pname ) 	
        xmlNodePtr elem
        SV * pname
    PREINIT:
        xmlChar *name = NULL;
        xmlDocPtr real_dom = NULL;
    CODE:
        if ( elem != NULL && pname != NULL && pname!=&PL_sv_undef ){
            name  = nodeSv2C( pname , elem );

            xmlRemoveProp( xmlHasProp( elem, name ) );	
            xmlFree(name);
        }

void
removeAttributeNS( elem, nsURI, pname )
        xmlNodePtr elem
        char * nsURI
        SV * pname
    PREINIT:
        xmlChar *prefix;
        xmlChar *lname = NULL;
        xmlNsPtr ns = NULL;
        xmlChar *name = NULL;
        xmlDocPtr real_dom = NULL;
    CODE:
        if ( elem != NULL && pname != NULL && pname!=&PL_sv_undef ){
            name  = nodeSv2C( pname , elem );

            if ( nsURI != NULL ) {
                lname = xmlSplitQName2(name, &prefix);
                if (lname == NULL) /* as it is supposed to be */
                    lname = name;
                /* ignore the given prefix if any, and use whatever
                   is defined in scope for this nsURI */
                ns = xmlSearchNsByHref(elem->doc, elem, nsURI);
                xmlUnsetNsProp( elem, ns, lname );
            }
            else {
                xmlRemoveProp( xmlHasProp( elem, name ) );	
            }
            xmlFree( name );
        }
        

void
getChildrenByTagName( elem, pname )
        SV* elem
        SV * pname 
    PREINIT:
        xmlNodePtr node;
        xmlNodeSetPtr nodelist;
        SV * element;
        int len = 0;
        int wantarray = GIMME_V;
        xmlChar * name;
    PPCODE:
        node = getSvNode(elem);
        name  = nodeSv2C( pname , node );
        nodelist = domGetElementsByTagName( node , name );
        xmlFree(name);
        if ( nodelist && nodelist->nodeNr > 0 ) {
            int i = 0 ;
            xmlNodePtr tnode;

            len = nodelist->nodeNr;
            if( wantarray == G_ARRAY ) {
                for( i ; i < len; i++){
                /* we have to create a new instance of an objectptr. and then 
                 * place the current node into the new object. afterwards we can 
                 * push the object to the array!
                 */
                    element = NULL;
                    tnode = nodelist->nodeTab[i];
                    element = nodeToSv(tnode);
                
                    if ( getSvNodeExtra != NULL ) {
                        setSvNodeExtra(element, getSvNodeExtra(elem));
                    }
                    XPUSHs( element );
                }
            }
            else {
                XPUSHs( newSViv( len ) );
            }
            xmlXPathFreeNodeSet( nodelist );
        }         

void
getChildrenByTagNameNS( elem, nsURI, pname )
        SV* elem
        char * nsURI
        SV * pname 
    PREINIT:
        xmlNodePtr node;
        xmlNodeSetPtr nodelist;
        xmlChar * name;
        SV * element;
        int len = 0;
        int wantarray = GIMME_V;
    PPCODE:
        node = getSvNode(elem);
        name = nodeSv2C(pname,node);
        nodelist = domGetElementsByTagNameNS( node , nsURI , name );
        xmlFree(name);
        if ( nodelist && nodelist->nodeNr > 0 ) {
            int i = 0 ;
            xmlNodePtr tnode;

            len = nodelist->nodeNr;
            if( wantarray == G_ARRAY ) {
                for( i ; i < len; i++){
                /* we have to create a new instance of an objectptr. and then 
                 * place the current node into the new object. afterwards we can 
                 * push the object to the array!
                 */
                    element = NULL;
                    tnode = nodelist->nodeTab[i];
                    element = nodeToSv(tnode);
                
                    if ( getSvNodeExtra(elem) != NULL ) {
                        setSvNodeExtra(element, getSvNodeExtra(elem));
                    }
                    XPUSHs( element );
                }
            }
            else {
                XPUSHs( newSViv( len ) );
            }
            xmlXPathFreeNodeSet( nodelist );
        }

void
appendWellBalancedChunk( self, chunk )
        xmlNodePtr self
        SV * chunk
    PREINIT:
        xmlChar * encvalue;
        xmlNodePtr rv;
        xmlDocPtr real_dom = NULL;
    CODE:
        if ( self != NULL 
             && chunk != NULL
             && chunk != &PL_sv_undef ) {
            encvalue = nodeSv2C(chunk, self);

            LibXML_error = sv_2mortal(newSVpv("", 0));
            rv = domReadWellBalancedString( self->doc, encvalue );
            LibXML_cleanup_callbacks();
            LibXML_cleanup_parser();

            if ( rv != NULL ) {
                xmlAddChildList( self , rv );
            }	
            if( encvalue != NULL )
                xmlFree( encvalue );
        }

void 
appendTextNode( self, xmlString )
        xmlNodePtr self
        SV * xmlString
    ALIAS:
        XML::LibXML::Element::appendText = 1
    PREINIT: 
        xmlDocPtr real_dom= NULL;
        xmlChar * encvalue = NULL;
    CODE:
        if ( self != NULL 
             && xmlString != NULL
             && xmlString != &PL_sv_undef ) {
            encvalue = nodeSv2C(xmlString, self);

            domAppendChild( self, xmlNewText( encvalue ) );
            xmlFree(encvalue);
        }

void 
appendTextChild( self, childname, xmlString )
        xmlNodePtr self
        SV * childname
        SV * xmlString
    PREINIT:
        xmlChar * encname = NULL;
        xmlChar * enccontent= NULL;
        xmlDocPtr real_dom = NULL;
    CODE:
        if ( self != NULL ) {
            enccontent = nodeSv2C(xmlString, self);
            encname = nodeSv2C(childname, self);

            xmlNewTextChild( self, NULL, encname, enccontent );
            xmlFree(encname);
            xmlFree(enccontent);
        }

MODULE = XML::LibXML         PACKAGE = XML::LibXML::PI

void
_setData( node, value )
        xmlNodePtr node
        SV * value
    PREINIT:
        xmlDocPtr real_dom = NULL;
        xmlChar * encstr;
    CODE:
        if ( node != NULL ) {
            encstr = nodeSv2C(value,node);
            domSetNodeValue( node, encstr );
            xmlFree( encstr );
        }

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Text

void
setData( node, value )
        xmlNodePtr node
        SV * value
    ALIAS:
        XML::LibXML::Attr::setValue = 1 
        # XML::LibXML::PI::_setData = 2
    PREINIT:
        xmlChar * encstr = NULL;
    CODE:
        if ( node != NULL ) {
            encstr = nodeSv2C(value,node);
            domSetNodeValue( node, encstr );
            xmlFree(encstr);
        }

SV *
new( CLASS, content )
        const char * CLASS
        SV * content
    PREINIT:
        xmlChar * data;
        xmlNodePtr newNode;
    CODE:
        /* we should test if this is UTF8 ... because this WILL cause
         * problems with iso encoded strings :(
         */
        data = Sv2C(content, NULL);
        newNode = xmlNewText( data );
        xmlFree(data);
        if( newNode != NULL ) {
            # init the keeping fragment
            xmlNodePtr docfrag = NULL;
            SV * docfrag_sv = NULL;

            docfrag = xmlNewDocFragment(NULL);
            docfrag_sv = nodeToSv(docfrag); 
            setSvNodeExtra(docfrag_sv,docfrag_sv);
                     
            domAppendChild( docfrag, newNode );            

            RETVAL = nodeToSv(newNode);
            setSvNodeExtra(RETVAL,docfrag_sv);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Comment

SV *
new( CLASS, content ) 
        const char * CLASS
        SV * content
    PREINIT:
        xmlChar * encstring;
        xmlNodePtr newNode;
    CODE:
        encstring = Sv2C(content, NULL);
        newNode = xmlNewComment( encstring );
        xmlFree(encstring);
        if( newNode != NULL ) {
            xmlNodePtr docfrag = NULL;
            SV * docfrag_sv = NULL;

            docfrag = xmlNewDocFragment(NULL);
            docfrag_sv = nodeToSv(docfrag); 
            setSvNodeExtra(docfrag_sv,docfrag_sv);
                     
            domAppendChild( docfrag, newNode );            

            RETVAL = nodeToSv(newNode);
            setSvNodeExtra(RETVAL,docfrag_sv);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::CDATASection

SV *
new( CLASS , content )
        const char * CLASS
        SV * content
    PREINIT:
        xmlChar * encstring;
        xmlNodePtr newNode;
    CODE:
        encstring = Sv2C(content, NULL);
        newNode = xmlNewCDataBlock( 0 , encstring, xmlStrlen( encstring ) );
        xmlFree(encstring);
        if ( newNode != NULL ){
            # init the keeping fragment
            xmlNodePtr docfrag = NULL;
            SV * docfrag_sv = NULL;

            docfrag = xmlNewDocFragment(NULL);
            docfrag_sv = nodeToSv(docfrag); 
            setSvNodeExtra(docfrag_sv,docfrag_sv);

            domAppendChild( docfrag, newNode );            

            RETVAL = nodeToSv(newNode);
            setSvNodeExtra(RETVAL,docfrag_sv);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Attr

SV *
new( CLASS , name="", value="" )
        char * CLASS
        char * name
        char * value
    PREINIT:
        xmlNodePtr attr = NULL;
    CODE:
        attr = (xmlNodePtr)xmlNewProp( NULL, name, value );
        attr->doc = NULL;
        RETVAL = nodeToSv(attr);
    OUTPUT:
        RETVAL

void
DESTROY(self)
        SV * self
    CODE:
        if (self != NULL || self != &PL_sv_undef ) {
            xmlNodePtr object = getSvNode(self);
            if ( object != NULL 
              && object->parent == NULL ) {
                object->doc = NULL;
                xmlFreeProp((xmlAttrPtr)object);            
                # warn( "REAL ATTRIBUTE DROPPED" );
            }
            free_proxy_node(self);
        }
        else {
            XSRETURN_UNDEF;
        }

SV *
getOwnerElement( attrnode ) 
        SV * attrnode 
    ALIAS:
        XML::LibXML::Attr::ownerElement = 1
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr attr;
        xmlNodePtr parent;
    CODE:
        attr   = (xmlNodePtr)getSvNode(attrnode);
        parent = attr->parent;
        if ( parent != NULL ) {
            RETVAL = nodeToSv(parent);
            setSvNodeExtra(RETVAL,getSvNodeExtra(attrnode));
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
getParentElement( attrnode )
        ProxyObject * attrnode
    ALIAS:
        XML::LibXML::Attr::parentNode = 1
    CODE:
        XSRETURN_UNDEF;
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::DocumentFragment

SV*
new( CLASS )
        char * CLASS
    PREINIT:
        SV * frag_sv = NULL;
        xmlNodePtr real_dom=NULL;
    CODE:
        real_dom = xmlNewDocFragment( NULL ); 
        RETVAL = nodeToSv( real_dom );
        setSvNodeExtra(RETVAL,RETVAL);
    OUTPUT:
        RETVAL

void
DESTROY(self)
        SV* self
    PREINIT:
        xmlNodePtr object;
    CODE:
        if (self != NULL || self != &PL_sv_undef ) {
            xs_warn("destroy fragment");
            /* check if the refcnt is 0 or 1 */
            object = getSvNode(self);
            if ( object != NULL ) {
                xmlFreeNode(object);
            }
            free_proxy_node(self);
        }

MODULE = XML::LibXML        PACKAGE = XML::LibXML::Namespace

SV *
getName (self)
        xmlNsPtr self
    ALIAS:
        XML::LibXML::Namespace::name = 1
    CODE:
        if (self->prefix != NULL && strlen(self->prefix) > 0) {
            RETVAL = newSVpv("xmlns:", 0);
            sv_catpv(RETVAL, (char*)self->prefix);
        } else {
            RETVAL = newSVpv("xmlns", 0);
        }
    OUTPUT:
        RETVAL
        
SV *
prefix (self)
        xmlNsPtr self
    ALIAS:
        XML::LibXML::Namespace::getLocalName = 1
        XML::LibXML::Namespace::localName = 2
    CODE:
        RETVAL = C2Sv(self->prefix, NULL);
    OUTPUT:
        RETVAL


SV *
getData (self)
        xmlNsPtr self
    ALIAS:
        XML::LibXML::Namespace::value = 1
        XML::LibXML::Namespace::getValue = 2
        XML::LibXML::Namespace::uri = 3
    CODE:
        RETVAL = C2Sv(self->href, NULL);
    OUTPUT:
        RETVAL

char *
getNamespaceURI (self)
        xmlNsPtr self
    CODE:
        RETVAL = "http://www.w3.org/2000/xmlns/";
    OUTPUT:
        RETVAL

char *
getPrefix (self)
        xmlNsPtr self
    CODE:
        RETVAL = "xmlns";
    OUTPUT:
        RETVAL

int
getPointer( self )
        xmlNsPtr self
    CODE:
        RETVAL = (int)self;
    OUTPUT:
        RETVAL
