/* $Id$ */

#ifdef __cplusplus
extern "C" {
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
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

typedef struct _ProxyObject ProxyObject;

struct _ProxyObject {
    void * object;
    SV * extra;
    /* ProxyObject * next; */
};

static SV * LibXML_match_cb = NULL;
static SV * LibXML_read_cb = NULL;
static SV * LibXML_open_cb = NULL;
static SV * LibXML_close_cb = NULL;
static SV * LibXML_error = NULL;

/* this should keep the default */
static xmlExternalEntityLoader LibXML_old_ext_ent_loader = NULL;

ProxyObject *
make_proxy_node (xmlNodePtr node)
{
    ProxyObject * proxy;
 
    proxy = (ProxyObject*)New(0, proxy, 1, ProxyObject);
    if (proxy != NULL) {
        proxy->object = (void*)node;
        proxy->extra = NULL;
    }
    return proxy;
}

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

    if ((global_cb = perl_get_sv("XML::LibXML::match_cb", FALSE))
            && SvTRUE(global_cb)) {
        callback = global_cb;
    }
    else if (LibXML_match_cb && SvTRUE(LibXML_match_cb)) {
        callback = LibXML_match_cb;
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

    if ((global_cb = perl_get_sv("XML::LibXML::open_cb", FALSE))
            && SvTRUE(global_cb)) {
        callback = global_cb;
    }
    else if (LibXML_open_cb && SvTRUE(LibXML_open_cb)) {
        callback = LibXML_open_cb;
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

    if ((global_cb = perl_get_sv("XML::LibXML::read_cb", FALSE))
            && SvTRUE(global_cb)) {
        callback = global_cb;
    }
    else if (LibXML_read_cb && SvTRUE(LibXML_read_cb)) {
        callback = LibXML_read_cb;
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

    if ((global_cb = perl_get_sv("XML::LibXML::close_cb", FALSE))
            && SvTRUE(global_cb)) {
        callback = global_cb;
    }
    else if (LibXML_close_cb && SvTRUE(LibXML_close_cb)) {
        callback = LibXML_close_cb;
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
    
    sv_catsv(LibXML_error, sv); /* remember the last error */
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
    
    sv_catsv(LibXML_error, sv);
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
    
    if (!well_formed || (xmlDoValidityCheckingDefaultValue && !valid)) {
        xmlFreeDoc(doc);
        return NULL;
    }
    /* this should be done by libxml2 !? */
    if (doc->encoding == NULL) {
        doc->encoding = xmlStrdup("utf-8");
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
}

void
LibXML_init_callbacks() {
    xmlSetGenericErrorFunc(PerlIO_stderr(), 
                           (xmlGenericErrorFunc)LibXML_error_handler);
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
    xmlSetGenericErrorFunc(NULL, NULL);
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

SV *
_match_callback(self, ...)
        SV * self
    CODE:
        if (items > 1) {
            SET_CB(LibXML_match_cb, ST(1));
            /* LibXML_update_callbacks(); */
        }
        else {
            RETVAL = LibXML_match_cb ? sv_2mortal(LibXML_match_cb) : &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

SV *
_open_callback(self, ...)
        SV * self
    CODE:
        if (items > 1) {
            SET_CB(LibXML_open_cb, ST(1));
            /* LibXML_update_callbacks(); */

        }
        else {
            RETVAL = LibXML_open_cb ? sv_2mortal(LibXML_open_cb) : &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

SV *
_read_callback(self, ...)
        SV * self
    CODE:
        if (items > 1) {
            SET_CB(LibXML_read_cb, ST(1));
            /* LibXML_update_callbacks(); */
        }
        else {
            RETVAL = LibXML_read_cb ? sv_2mortal(LibXML_read_cb) : &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

SV *
_close_callback(self, ...)
        SV * self
    CODE:
        if (items > 1) {
            SET_CB(LibXML_close_cb, ST(1));
            /* LibXML_update_callbacks(); */
        }
        else {
            RETVAL = LibXML_close_cb ? sv_2mortal(LibXML_close_cb) : &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

int
_validation(self, ...)
        SV * self
    CODE:
        /* init retval with the current default value */
        RETVAL = xmlDoValidityCheckingDefaultValue; 
        if (items > 1) {
            xmlDoValidityCheckingDefaultValue = SvTRUE(ST(1)) ? 1 : 0;
        }
    OUTPUT:
        RETVAL

int
_expand_entities(self, ...)
        SV * self
    CODE:
        RETVAL = xmlSubstituteEntitiesDefaultValue;
        if (items > 1) {
            xmlSubstituteEntitiesDefaultValue = SvTRUE(ST(1)) ? 1 : 0;
        }
    OUTPUT:
        RETVAL

int
_keep_blanks(self, ...)
        SV * self
    CODE:
        RETVAL = xmlKeepBlanksDefaultValue;
        if (items > 1) {
            xmlKeepBlanksDefaultValue = SvTRUE(ST(1)) ? 1 : 0;
        }
    OUTPUT:
        RETVAL

int
_pedantic_parser(self, ...)
        SV * self
    CODE:
        RETVAL = xmlPedanticParserDefaultValue;
        if (items > 1)  {
            xmlPedanticParserDefaultValue = SvTRUE(ST(1)) ? 1 : 0;
        }
    OUTPUT:
        RETVAL

int
_load_ext_dtd(self, ...)
        SV * self
    CODE:
        RETVAL = ( xmlLoadExtDtdDefaultValue == (xmlLoadExtDtdDefaultValue | 1 ) );
        if (items > 1) {
            if (SvTRUE(ST(1)))
                xmlLoadExtDtdDefaultValue |= 1;
            else 
                xmlLoadExtDtdDefaultValue ^= 1;
            RETVAL = ( xmlLoadExtDtdDefaultValue == (xmlLoadExtDtdDefaultValue | 1 ) );
        }
    OUTPUT:
        RETVAL

int
_complete_attributes(self, ...)
        SV * self
    CODE:
        RETVAL = ( xmlLoadExtDtdDefaultValue == (xmlLoadExtDtdDefaultValue | XML_COMPLETE_ATTRS));
        if (items > 1) {
            if (SvTRUE(ST(1)))
                xmlLoadExtDtdDefaultValue |= XML_COMPLETE_ATTRS;
            else
                xmlLoadExtDtdDefaultValue ^= XML_COMPLETE_ATTRS;
        }
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
        LibXML_init_callbacks();
        ret = xmlParseDocument(ctxt);
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();

        # warn( "document parsed \n");

        ctxt->directory = NULL;

        well_formed = ctxt->wellFormed;
        valid = ctxt->valid;

        real_dom = ctxt->myDoc;
        xmlFreeParserCtxt(ctxt);
        sv_2mortal(LibXML_error);
        if (!well_formed || (xmlDoValidityCheckingDefaultValue && !valid)) {
            xmlFreeDoc(real_dom);
            RETVAL = &PL_sv_undef;    
            croak(SvPV(LibXML_error, len));
        }
        else {
            STRLEN n_a;
            SV * newURI = newSVpvf("unknown-%12.12d", real_dom);
            real_dom->URL = xmlStrdup(SvPV(newURI, n_a));
            SvREFCNT_dec(newURI);
            proxy = make_proxy_node( (xmlNodePtr)real_dom ); 
            RETVAL = sv_newmortal();
            sv_setref_pv( RETVAL, (char *)CLASS, (void*)proxy );
            proxy->extra = RETVAL;
            SvREFCNT_inc(RETVAL);
        }
 
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

        LibXML_init_callbacks();
        real_dom = LibXML_parse_stream(self, fh, directory);
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();

        sv_2mortal(LibXML_error);
        
        if (real_dom == NULL) {
            RETVAL = &PL_sv_undef;    
            croak(SvPV(LibXML_error, len));
        }
        else {
            STRLEN n_a;
            SV * newURI = newSVpvf("unknown-%12.12d", real_dom);
            real_dom->URL = xmlStrdup(SvPV(newURI, n_a));
            SvREFCNT_dec(newURI);
            proxy = make_proxy_node( (xmlNodePtr)real_dom ); 

            RETVAL = sv_newmortal();
            sv_setref_pv( RETVAL, (char *)CLASS, (void*)proxy );
            proxy->extra = RETVAL;
            SvREFCNT_inc(RETVAL);
        }
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
        ctxt = xmlCreateFileParserCtxt(filename);

        if (ctxt == NULL) {
            croak("Could not create file parser context for file '%s' : %s", filename, strerror(errno));
        }
        ctxt->_private = (void*)self;
        
        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);

        LibXML_init_callbacks();        
        xmlParseDocument(ctxt);
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();

        well_formed = ctxt->wellFormed;
        valid = ctxt->valid;

        real_dom = ctxt->myDoc;
        xmlFreeParserCtxt(ctxt);
        
        sv_2mortal(LibXML_error);
        
        if (!well_formed || (xmlDoValidityCheckingDefaultValue && !valid)) {
            xmlFreeDoc(real_dom);
            RETVAL = &PL_sv_undef ;  
            croak(SvPV(LibXML_error, len));
        }
        else {
            proxy = make_proxy_node( (xmlNodePtr)real_dom ); 

            RETVAL = sv_newmortal();
            sv_setref_pv( RETVAL, (char *)CLASS, (void*)proxy );
            proxy->extra = RETVAL;
            SvREFCNT_inc(RETVAL);
        }
    OUTPUT:
        RETVAL

SV*
_parse_html_string(self, string)
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
        
        LibXML_init_callbacks();
        real_dom = htmlParseDoc(ptr, NULL);
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();        

        sv_2mortal(LibXML_error);
        
        if (!real_dom) {
            RETVAL = &PL_sv_undef;    
            croak(SvPV(LibXML_error, len));
        }
        else {
            STRLEN n_a;
            SV * newURI = newSVpvf("unknown-%12.12d", real_dom);
            real_dom->URL = xmlStrdup(SvPV(newURI, n_a));
            SvREFCNT_dec(newURI);
            proxy = make_proxy_node( (xmlNodePtr)real_dom ); 
             RETVAL = sv_newmortal();
            sv_setref_pv( RETVAL, (char *)CLASS, (void*)proxy );
            proxy->extra = RETVAL;
            SvREFCNT_inc(RETVAL);
        }
    OUTPUT:
        RETVAL

SV*
_parse_html_fh(self, fh)
        SV * self
        SV * fh
    PREINIT:
        char * CLASS = "XML::LibXML::Document";
        STRLEN len;
        xmlDocPtr real_dom;
        ProxyObject* proxy;
    CODE:
        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);
        
        LibXML_init_callbacks();
        real_dom = LibXML_parse_html_stream(self, fh);
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();
        
        sv_2mortal(LibXML_error);
        
        if (real_dom == NULL) {
            RETVAL = &PL_sv_undef;    
            croak(SvPV(LibXML_error, len));
        }
        else {
            STRLEN n_a;
            SV * newURI = newSVpvf("unknown-%12.12d", real_dom);
            real_dom->URL = xmlStrdup(SvPV(newURI, n_a));
            SvREFCNT_dec(newURI);
            proxy = make_proxy_node( (xmlNodePtr)real_dom ); 
             RETVAL = sv_newmortal();
            sv_setref_pv( RETVAL, (char *)CLASS, (void*)proxy );
            proxy->extra = RETVAL;
            SvREFCNT_inc(RETVAL);
        }
    OUTPUT:
        RETVAL
        
SV*
_parse_html_file(self, filename)
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
        
        LibXML_init_callbacks();
        real_dom = htmlParseFile(filename, NULL);
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();

        sv_2mortal(LibXML_error);
        
        if (!real_dom) {
            RETVAL = &PL_sv_undef ;  
            croak(SvPV(LibXML_error, len));
        }
        else {
            proxy = make_proxy_node( (xmlNodePtr)real_dom ); 
             RETVAL = sv_newmortal();
            sv_setref_pv( RETVAL, (char *)CLASS, (void*)proxy );
            proxy->extra = RETVAL;
            SvREFCNT_inc(RETVAL);
        }
    OUTPUT:
        RETVAL

SV*
_parse_xml_chunk( self, chunk, encoding="UTF-8" )
        SV * self
        char * chunk
        char * encoding
    PREINIT:
        char * CLASS = "XML::LibXML::DocumentFragment";
        xmlNodePtr rv = NULL;
        xmlNodePtr fragment= NULL;
        ProxyObject *ret=NULL;
        xmlNodePtr rv_end = NULL;
    CODE:
        if ( encoding == NULL ) encoding = "UTF-8";

        chunk = domEncodeString( encoding, chunk );

        if ( chunk != NULL ) {
            LibXML_error = sv_2mortal(newSVpv("", 0));
            LibXML_init_callbacks();
            rv = domReadWellBalancedString( NULL, chunk );
            LibXML_cleanup_callbacks();
            LibXML_cleanup_parser();    

            if ( rv != NULL ) {
                /* now we append the nodelist to a document
                   fragment which is unbound to a Document!!!! */
                # warn( "good chunk, create fragment" );

                /* step 1: create the fragment */
                fragment = xmlNewDocFragment( NULL );
                # if ( !fragment ) warn( "no fragment!\n" );
                ret = make_proxy_node( fragment );
                RETVAL = NEWSV(0,0);
                sv_setref_pv( RETVAL, (char *)CLASS, (void*)ret );
                ret->extra = RETVAL;
                # warn( "NEW FRAGMENT DOCUMENT" );
                # SvREFCNT_inc(RETVAL);

                /* step 2: set the node list to the fragment */
                fragment->children = rv;
                rv->parent = fragment;
                rv_end = rv;
                while ( rv_end->next != NULL ) {
                    rv_end = rv_end->next;
                    rv_end->parent = fragment;
                }
                fragment->last = rv_end;
            }
            else {
                # warn( "bad chunk" );
                RETVAL = &PL_sv_undef;
            }
            /* free the chunk we created */
            xmlFree( chunk );
        }
    OUTPUT:
        RETVAL

SV*
encodeToUTF8( encoding, string )
        const char * encoding
        const char * string
    PREINIT:
        char * tstr;
    CODE:
        tstr =  domEncodeString( encoding, string );
        RETVAL = newSVpvn( (char *)tstr, xmlStrlen( tstr ) );
        xmlFree( tstr ); 
    OUTPUT:
        RETVAL

SV*
decodeFromUTF8( encoding, string ) 
        const char * encoding
        const char * string
    PREINIT:
        char * tstr;
    CODE: 
        tstr =  domDecodeString( encoding, string );
        RETVAL = newSVpvn( (char *)tstr, xmlStrlen( tstr ) );
        xmlFree( tstr ); 
    OUTPUT:
        RETVAL


MODULE = XML::LibXML         PACKAGE = XML::LibXML::Document

void
_fix_extra(node_sv)
        SV * node_sv
    PREINIT:
        ProxyObject* node;
    CODE:
        node = (ProxyObject *)SvIV((SV*)SvRV(node_sv));
        node->extra = node_sv;

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
            cvp.userData = (void*)PerlIO_stderr();
            cvp.error = (xmlValidityErrorFunc)LibXML_validity_error;
            cvp.warning = (xmlValidityWarningFunc)LibXML_validity_warning;
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
            cvp.userData = (void*)PerlIO_stderr();
            cvp.error = (xmlValidityErrorFunc)LibXML_validity_error;
            cvp.warning = (xmlValidityWarningFunc)LibXML_validity_warning;
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
        ProxyObject* self
    CODE:
        LibXML_init_callbacks();
        xmlXIncludeProcess((xmlDocPtr)self->object);
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();

const char *
URI (doc, new_URI=NULL)
        xmlDocPtr doc
        char * new_URI
    CODE:
        RETVAL = xmlStrdup( doc->URL );
        if (new_URI) {
            xmlFree( (char*) doc->URL);
            doc->URL = xmlStrdup(new_URI);
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
        ret = make_proxy_node( (xmlNodePtr)real_dom );
        RETVAL = NEWSV(0,0);
        sv_setref_pv( RETVAL, (char *)CLASS, (void*)ret );
        ret->extra = RETVAL;
    OUTPUT:
        RETVAL

SV*
createDocumentFragment( dom )
        SV * dom
    PREINIT:
        SV * frag_sv = NULL;
        xmlDocPtr real_dom;
        xmlNodePtr fragment= NULL;
        ProxyObject *ret=NULL;
        const char * CLASS = "XML::LibXML::DocumentFragment";
    CODE:
        real_dom = (xmlDocPtr)((ProxyObject*)SvIV((SV*)SvRV(dom)))->object;
        fragment = xmlNewDocFragment( real_dom );
        ret = make_proxy_node( fragment );
        RETVAL = NEWSV(0,0);
        sv_setref_pv( RETVAL, (char *)CLASS, (void*)ret );
        ret->extra = RETVAL;
        # warn( "NEW FRAGMENT DOCUMENT" );
        SvREFCNT_inc(RETVAL);
    OUTPUT:
        RETVAL

ProxyObject *
createElement( dom, name )
        SV * dom
        char* name
    PREINIT:
        char * CLASS = "XML::LibXML::Element";
        xmlNodePtr newNode;
        xmlDocPtr real_dom;
        xmlNodePtr docfrag = NULL;
        ProxyObject * dfProxy= NULL;
        xmlChar * elname = NULL;
        SV * docfrag_sv = NULL;
    CODE:
        real_dom = (xmlDocPtr)((ProxyObject*)SvIV((SV*)SvRV(dom)))->object;

        docfrag = xmlNewDocFragment( real_dom );
        dfProxy = make_proxy_node( docfrag );
        docfrag_sv = NEWSV(0,0);
        sv_setref_pv( docfrag_sv, "XML::LibXML::DocumentFragment", (void*)dfProxy );
        dfProxy->extra = docfrag_sv;
        # warn( "NEW FRAGMENT ELEMNT (%s)", name);
        # SvREFCNT_inc(docfrag_sv);    

        # warn("xmlNewNode\n");
        elname = domEncodeString( real_dom->encoding, name);
        newNode = xmlNewNode( NULL , elname );
        xmlFree(elname);
        
        newNode->doc = real_dom;
        domAppendChild( docfrag, newNode );
        # warn( newNode->name );
        RETVAL = make_proxy_node(newNode);
        RETVAL->extra = docfrag_sv;
    OUTPUT:
        RETVAL

ProxyObject *
createElementNS( dom, nsURI, qname)
         SV * dom
         char *nsURI
         char* qname 
     PREINIT:
         char * CLASS = "XML::LibXML::Element";
         xmlNodePtr newNode;
         xmlChar *prefix;
         xmlChar *lname = NULL;
         xmlNsPtr ns = NULL;
         xmlDocPtr real_dom;
         xmlNodePtr docfrag = NULL;
         xmlChar * encstring = NULL;
         ProxyObject * dfProxy= NULL;
         SV * docfrag_sv = NULL;
     CODE:
        real_dom = (xmlDocPtr)((ProxyObject*)SvIV((SV*)SvRV(dom)))->object;

        docfrag = xmlNewDocFragment( real_dom );
        dfProxy = make_proxy_node( docfrag );
        docfrag_sv = NEWSV(0,0);
        sv_setref_pv( docfrag_sv, "XML::LibXML::DocumentFragment", (void*)dfProxy );
        dfProxy->extra = docfrag_sv;
        # warn( "NEW FRAGMENT ELEMENT NS (%s)", qname);
        # SvREFCNT_inc(docfrag_sv);    

        if ( nsURI != NULL && strlen(nsURI)!=0 ){
            lname = xmlSplitQName2(qname, &prefix);
            encstring = domEncodeString( real_dom->encoding, prefix );
            ns = domNewNs (0 , encstring, nsURI );
            xmlFree(encstring);
        }
        else {
            lname = qname;
        }
        encstring = domEncodeString( real_dom->encoding, lname );
        newNode = xmlNewNode( ns , encstring );
        xmlFree(encstring);

        newNode->doc = real_dom;
        domAppendChild( docfrag, newNode );

        RETVAL = make_proxy_node(newNode);
        RETVAL->extra = docfrag_sv;
     OUTPUT:
        RETVAL

ProxyObject *
createTextNode( dom, content )
        SV * dom
        char * content
    PREINIT:
        char * CLASS = "XML::LibXML::Text";
        xmlNodePtr newNode;
        xmlDocPtr real_dom;
        xmlNodePtr docfrag = NULL;
        ProxyObject * dfProxy= NULL;
        xmlChar * encstring = NULL;
        SV * docfrag_sv = NULL;
    CODE:
        real_dom = (xmlDocPtr)((ProxyObject*)SvIV((SV*)SvRV(dom)))->object;

        docfrag = xmlNewDocFragment( real_dom );
        dfProxy = make_proxy_node( docfrag );
        docfrag_sv =sv_newmortal();
        sv_setref_pv( docfrag_sv, "XML::LibXML::DocumentFragment", (void*)dfProxy );
        dfProxy->extra = docfrag_sv;
        # warn( "NEW FRAGMENT TEXT");
        # SvREFCNT_inc(docfrag_sv);    

        encstring = domEncodeString( real_dom->encoding, content );
        newNode = xmlNewDocText( real_dom, encstring );
        xmlFree(encstring);

        domAppendChild( docfrag, newNode );

        RETVAL = make_proxy_node(newNode);
        RETVAL->extra = docfrag_sv;
        SvREFCNT_inc(docfrag_sv);
    OUTPUT:
        RETVAL

ProxyObject *
createComment( dom , content )
        SV * dom
        char * content
    PREINIT:
        char * CLASS = "XML::LibXML::Comment";
        xmlNodePtr newNode;
        xmlDocPtr real_dom;
        xmlNodePtr docfrag = NULL;
        ProxyObject * dfProxy= NULL;
        SV * docfrag_sv = NULL;
    CODE:
        real_dom = (xmlDocPtr)((ProxyObject*)SvIV((SV*)SvRV(dom)))->object;
        content = domEncodeString( real_dom->encoding, content );
        
        newNode = xmlNewDocComment( real_dom, content );
        
        docfrag = xmlNewDocFragment( real_dom );
        dfProxy = make_proxy_node( docfrag );
        docfrag_sv =sv_newmortal();
        sv_setref_pv( docfrag_sv, "XML::LibXML::DocumentFragment", (void*)dfProxy );
        dfProxy->extra = docfrag_sv;
        # warn( "NEW FRAGMENT COMMENT");
        # SvREFCNT_inc(docfrag_sv);    
        domAppendChild( docfrag, newNode );

        RETVAL = make_proxy_node(newNode);
        RETVAL->extra = docfrag_sv;
        SvREFCNT_inc(docfrag_sv);
    OUTPUT:
        RETVAL

ProxyObject *
createCDATASection( dom, content )
        SV * dom
        char * content
    PREINIT:
        char * CLASS = "XML::LibXML::CDATASection";
        xmlNodePtr newNode;
        xmlDocPtr real_dom;
        xmlNodePtr docfrag = NULL;
        ProxyObject * dfProxy= NULL;
        SV * docfrag_sv = NULL;
    CODE:
        real_dom = (xmlDocPtr)((ProxyObject*)SvIV((SV*)SvRV(dom)))->object;
        content = domEncodeString( real_dom->encoding, content );

        newNode = domCreateCDATASection( real_dom, content );
        
        docfrag = xmlNewDocFragment( real_dom );
        dfProxy = make_proxy_node( docfrag );
        docfrag_sv =sv_newmortal();
        sv_setref_pv( docfrag_sv, "XML::LibXML::DocumentFragment", (void*)dfProxy );
        dfProxy->extra = docfrag_sv;
        # warn( "NEW FRAGMENT CDATA");
        # SvREFCNT_inc(docfrag_sv);    
        domAppendChild( docfrag, newNode );

        RETVAL = make_proxy_node(newNode);
        RETVAL->extra = docfrag_sv;
        SvREFCNT_inc(docfrag_sv);
    OUTPUT:
        RETVAL

ProxyObject *
createAttribute( dom, name , value="" )
        SV * dom
        char * name
        char * value
    PREINIT:
        const char* CLASS = "XML::LibXML::Attr";
        xmlNodePtr newNode;
        xmlDocPtr real_dom;
    CODE:
        real_dom = (xmlDocPtr)((ProxyObject*)SvIV((SV*)SvRV(dom)))->object;
        name  = domEncodeString( real_dom->encoding, name );
        value = domEncodeString( real_dom->encoding, value );
        
        newNode = (xmlNodePtr)xmlNewProp(NULL, name , value );
        xmlFree(name);
        xmlFree(value);
        newNode->doc = (xmlDocPtr)((ProxyObject*)SvIV((SV*)SvRV(dom)))->object;
        if ( newNode->children!=NULL ) {
            newNode->children->doc = (xmlDocPtr)((ProxyObject*)SvIV((SV*)SvRV(dom)))->object;
        }
        RETVAL = make_proxy_node(newNode);
        RETVAL->extra = dom;
        SvREFCNT_inc(dom);    
    OUTPUT:
        RETVAL

ProxyObject *
createAttributeNS( dom, nsURI, qname, value="" )
        SV * dom
        char * nsURI
        char * qname
        char * value
    PREINIT:
        const char* CLASS = "XML::LibXML::Attr";
        xmlNodePtr newNode;
        xmlChar *prefix;
        xmlChar *lname =NULL;
        xmlNsPtr ns=NULL;
        xmlDocPtr real_dom;
    CODE:
        real_dom = (xmlDocPtr)((ProxyObject*)SvIV((SV*)SvRV(dom)))->object;
        if ( nsURI != NULL && strlen( nsURI ) != 0 ){
            lname = xmlSplitQName2(qname, &prefix);
            ns = domNewNs (0 , prefix , nsURI);
        }
        else{
            lname = qname;
        }
        lname = domEncodeString( real_dom->encoding, lname );
        value = domEncodeString( real_dom->encoding, value );
        if ( ns != NULL ) {
            newNode = (xmlNodePtr) xmlNewNsProp(NULL, ns, lname , value );
        }
        else {
            newNode = (xmlNodePtr) xmlNewProp( NULL, lname, value );
        }
        
        xmlFree(lname);
        xmlFree(value);

        newNode->doc = real_dom;

        if ( newNode->children!=NULL ) {
            newNode->children->doc = real_dom;
        }
        RETVAL = make_proxy_node(newNode);
        RETVAL->extra = dom;
        SvREFCNT_inc(dom);    
    OUTPUT:
        RETVAL

void 
setDocumentElement( dom , proxy )
        SV * dom
        ProxyObject * proxy
    PREINIT:
        xmlDocPtr real_dom;
        xmlNodePtr elem;
        SV* oldsv =NULL;
    CODE:
        real_dom = (xmlDocPtr)((ProxyObject*)SvIV((SV*)SvRV(dom)))->object;
        elem = (xmlNodePtr)proxy->object;

        # please correct me if i am wrong: the document element HAS to be
        # an ELEMENT NODE
        if ( elem->type == XML_ELEMENT_NODE ) {
            if( proxy->extra != NULL ) {
                #warn( "decrease holder element" );
                oldsv = proxy->extra;
            }
            domSetDocumentElement( real_dom, elem );
            proxy->extra = dom;
            SvREFCNT_inc(dom);
            SvREFCNT_dec( oldsv );
        }

ProxyObject *
getDocumentElement( dom )
        SV * dom
    ALIAS:
        XML::LibXML::Document::documentElement = 1
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr elem;
        xmlDocPtr real_dom;
    CODE:
        real_dom = (xmlDocPtr)((ProxyObject*)SvIV((SV*)SvRV(dom)))->object;
        RETVAL = NULL;
        elem = domDocumentElement( real_dom ) ;
        if ( elem ) {
            CLASS = domNodeTypeName( elem );
            RETVAL = make_proxy_node(elem);
            RETVAL->extra = dom;
            SvREFCNT_inc(dom);
        }
    OUTPUT:
        RETVAL

void
insertProcessingInstruction( dom, name, content )
        SV * dom
        char * name 
        char * content
    ALIAS:
        insertPI = 1
    PREINIT:
        xmlNodePtr pinode = NULL;
        xmlDocPtr real_dom;
        xmlChar * enctarg;
        xmlChar * encdata;
    CODE:
        real_dom = (xmlDocPtr)((ProxyObject*)SvIV((SV*)SvRV(dom)))->object;
        enctarg = domEncodeString( real_dom->encoding, name );
        encdata = domEncodeString( real_dom->encoding, content );
        pinode = xmlNewPI( enctarg, encdata );
        
        xmlFree(enctarg);
        xmlFree(encdata);

        /* pinode = xmlNewPI( name, content ); */
        domInsertBefore( (xmlNodePtr)real_dom, 
                         pinode, 
                         domDocumentElement( real_dom ) );

ProxyObject *
createProcessingInstruction( dom, name, content="" )
        SV * dom
        char * name 
        char * content
    ALIAS:
        createPI = 1
    PREINIT:
        char * CLASS = "XML::LibXML::PI";
        xmlNodePtr newNode;
        xmlDocPtr real_dom;
        xmlNodePtr docfrag = NULL;
        ProxyObject * dfProxy= NULL;
        xmlChar * enctarg;
        xmlChar * encdata;
        SV * docfrag_sv = NULL;
    CODE:
        real_dom = (xmlDocPtr)((ProxyObject*)SvIV((SV*)SvRV(dom)))->object;

        docfrag = xmlNewDocFragment( real_dom );
        dfProxy = make_proxy_node( docfrag );
        docfrag_sv =sv_newmortal();
        sv_setref_pv( docfrag_sv, "XML::LibXML::DocumentFragment", (void*)dfProxy );
        dfProxy->extra = docfrag_sv;
        # warn( "NEW FRAGMENT ELEMNT (%s)", name);
        # SvREFCNT_inc(docfrag_sv);    

        enctarg = domEncodeString( real_dom->encoding, name );
        encdata = domEncodeString( real_dom->encoding, content );
        newNode = xmlNewPI( enctarg, encdata );
        xmlFree(enctarg);
        xmlFree(encdata);
        /* newNode = xmlNewPI( name, content ); */
        newNode->doc = real_dom;
        domAppendChild( docfrag, newNode );
        # warn( newNode->name );
        RETVAL = make_proxy_node(newNode);
        RETVAL->extra = docfrag_sv;
        SvREFCNT_inc(docfrag_sv);
    OUTPUT:
        RETVAL

ProxyObject *
importNode( dom, node, move=0 ) 
        SV * dom
        ProxyObject * node
        int move
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr ret = NULL;
        xmlNodePtr real_node = NULL;
        xmlDocPtr real_dom;
    CODE:
        real_dom = (xmlDocPtr)((ProxyObject*)SvIV((SV*)SvRV(dom)))->object;
        real_node= (xmlNodePtr)node->object;
        RETVAL = NULL;
        ret = domImportNode( real_dom, real_node, move );
        if ( ret ) {
            if ( node->extra != NULL && move == 0 ){
                SvREFCNT_dec( node->extra );
            }
            CLASS = domNodeTypeName( ret );
            RETVAL = make_proxy_node(ret);
            RETVAL->extra = dom;
            SvREFCNT_inc(dom);
        }
    OUTPUT:
        RETVAL

char*
getEncoding( self )
        ProxyObject* self
    CODE:
        if( self != NULL && self->object!=NULL) {
            RETVAL = xmlStrdup( ((xmlDocPtr)self->object)->encoding );
        }
    OUTPUT:
        RETVAL

void
setEncoding( self, encoding )
        ProxyObject* self
        char *encoding
    CODE:
        if( self != NULL && self->object!=NULL) {
            ((xmlDocPtr)self->object)->encoding = xmlStrdup( encoding );
        }

char*
getVersion( self ) 
         ProxyObject* self
    CODE:
        if( self != NULL && self->object != NULL) {
            RETVAL = xmlStrdup( ((xmlDocPtr)self->object)->version );
        }
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Dtd

ProxyObject *
new(CLASS, external, system)
        char * CLASS
        char * external
        char * system
    CODE:
        LibXML_error = sv_2mortal(newSVpv("", 0));
        RETVAL = make_proxy_node((xmlNodePtr)xmlParseDTD((const xmlChar*)external, (const xmlChar*)system));
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
        ProxyObject * node
    PREINIT:
        xmlNodePtr real_node;
    CODE:
        /* XXX should destroy node->extra if refcnt == 0 */
        if (node == NULL) {
           XSRETURN_UNDEF;
        }
        real_node = (xmlNodePtr)node->object;
        if ( node->extra != NULL
             && real_node != NULL ){
            if( real_node->type == XML_DOCUMENT_FRAG_NODE ) {
                warn( "NODE DESTROY: NODE ISA DOCUMENT_FRAGMENT!" );
            }

            if ( SvREFCNT( node->extra ) > 0 ){
                SvREFCNT_dec(node->extra);
            }
        }
        Safefree(node);

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
        ProxyObject * proxyelem
    PREINIT:
        xmlNodePtr elem       = NULL;
        xmlNodePtr docfrag    = NULL;
        ProxyObject * dfProxy = NULL;
        SV * docfrag_sv       = NULL;
    CODE:
        elem = (xmlNodePtr)proxyelem->object;
        domUnbindNode( elem );

        docfrag = xmlNewDocFragment( elem->doc );
        dfProxy = make_proxy_node( docfrag );
        docfrag_sv =sv_newmortal();
        sv_setref_pv( docfrag_sv,
                      "XML::LibXML::DocumentFragment", 
                      (void*)dfProxy );
        dfProxy->extra = docfrag_sv;
        #warn("NEW FRAGMENT ON NODE %s", elem->name);
        # SvREFCNT_inc(docfrag_sv);    

        domAppendChild( docfrag, elem );
        if( proxyelem->extra != NULL ){
            SvREFCNT_dec( proxyelem->extra );
        }    
        proxyelem->extra = docfrag_sv;
        SvREFCNT_inc(docfrag_sv);             

ProxyObject *
removeChild( paren, child ) 
        xmlNodePtr paren
        xmlNodePtr child
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr ret;
    CODE:
        ret = domRemoveChild( paren, child );
        RETVAL = NULL;
        if (ret != NULL) {
            CLASS = domNodeTypeName( ret );
            RETVAL = make_proxy_node(ret);
        }
    OUTPUT:
        RETVAL

ProxyObject *
replaceChild( paren, newChild, oldChild ) 
        ProxyObject* paren
        ProxyObject* newChild
        xmlNodePtr oldChild
    PREINIT:
        ProxyObject* pproxy = NULL;
        ProxyObject* cproxy = NULL;
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr ret;
    CODE:
        ret = domReplaceChild( paren->object, newChild->object, oldChild );
        RETVAL = NULL;
        if (ret != NULL) {
            CLASS = domNodeTypeName( ret );
            RETVAL = make_proxy_node(ret);
            
            if ( ((xmlNodePtr)paren->object)->type == XML_DOCUMENT_NODE ) {
                pproxy = paren;
            }
            else if ( paren->extra != NULL ){
                pproxy = (ProxyObject*)SvIV((SV*)SvRV(paren->extra));
            }
            if (  newChild->extra != NULL ) {
                cproxy = (ProxyObject*)SvIV((SV*)SvRV(newChild->extra));
            }
            if ( pproxy == NULL || 
                 cproxy == NULL || 
                 pproxy->object != cproxy->object ) {
      
                # warn("different documents");
                if ( newChild->extra != NULL ){
                    # warn("decrease child documents");   
                    SvREFCNT_dec(newChild->extra);
                }

                newChild->extra = paren->extra;
                RETVAL->extra   = paren->extra;

                if ( newChild->extra != NULL ){
                    # warn("increase child documents");   
                    SvREFCNT_inc(newChild->extra);
                    # SvREFCNT_inc(newChild->extra);
                }
            }
        }
    OUTPUT:
        RETVAL

void
appendChild( parent, child )
        ProxyObject* parent
        ProxyObject* child
    PREINIT:
        ProxyObject* pproxy = NULL;
        ProxyObject* cproxy = NULL;
        xmlNodePtr test = NULL;
    CODE:
        if ( parent == NULL ) {
               croak("parent problem!\n");
        }
        if ( child == NULL ) {
               croak("child problem!\n");
        }

        # warn( "append Child \n" );
        if (((xmlNodePtr)parent->object)->type == XML_DOCUMENT_NODE
             && ((xmlNodePtr)child->object)->type == XML_ELEMENT_NODE ) {
            # warn( "use setDocumentElement!!!!\n" );
            
        }
        else {
            # test = domAppendChild( parent->object, child->object );
            # update the proxies if nessecary
            # warn( "real append\n" );
            if ( domAppendChild( parent->object, child->object ) != NULL ) {

                # warn( "node appended\n" );    
                /* if we appended a fragment we do not need to change refcounts */
                if ( !((xmlNodePtr)parent->object)->type == XML_DOCUMENT_FRAG_NODE ) {
                    if ( ((xmlNodePtr)parent->object)->type == XML_DOCUMENT_NODE ) {
                        pproxy = parent;
                    }
                    else if ( parent->extra != NULL ){
                        pproxy = (ProxyObject*)SvIV((SV*)SvRV(parent->extra));
                    }

                    if ( child->extra != NULL ) {
                        # warn( "c1\n" );
                        cproxy = (ProxyObject*)SvIV((SV*)SvRV(child->extra));
                        # warn( "c2\n" );    
                    }

                    if ( child->extra == NULL
                         || parent->extra == NULL
                         || pproxy->object != cproxy->object ) {
      
                        # warn("different documents");
                        if ( child->extra != NULL ){
                            # warn("decrease child documents");   
                            SvREFCNT_dec(child->extra);
                        }

                        child->extra = parent->extra;

                        if ( child->extra != NULL ){
                            # warn("increase child documents");   
                            SvREFCNT_inc(child->extra);
                        }
                    }
                    else {
                        # warn( "object failure\n" );
                    }
                }
                else {
                    # warn( "fragment append!\n" );
                }
            }
            else {
                # warn("append problem ...\n");
            }
        }

ProxyObject *
cloneNode( self, deep ) 
        ProxyObject* self
        int deep
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr ret;
        xmlNodePtr docfrag = NULL;
        ProxyObject * dfProxy= NULL;
        SV * docfrag_sv = NULL;
    CODE:
        ret = xmlCopyNode( (xmlNodePtr)self->object, deep );
        RETVAL = NULL;
        if (ret != NULL) {
            docfrag = xmlNewDocFragment( ret->doc );
            dfProxy = make_proxy_node( docfrag );
            docfrag_sv =sv_newmortal();
            sv_setref_pv( docfrag_sv, "XML::LibXML::DocumentFragment", (void*)dfProxy );
            dfProxy->extra = docfrag_sv;
            # warn( "NEW FRAGMENT CLONE");
            # SvREFCNT_inc(docfrag_sv);    
            domAppendChild( docfrag, ret );            

            CLASS = domNodeTypeName( ret );
            RETVAL = make_proxy_node(ret);
            RETVAL->extra = docfrag_sv ;
            SvREFCNT_inc(docfrag_sv);                
        }
    OUTPUT:
        RETVAL


ProxyObject *
getParentNode( self )
        ProxyObject* self
    ALIAS:
        XML::LibXML::Node::parentNode = 1
    PREINIT:
        const char * CLASS = "XML::LibXML::Element";
        xmlNodePtr ret;
    CODE:
        ret = ((xmlNodePtr)self->object)->parent;
        RETVAL = NULL;
        if (ret != NULL) {
            RETVAL = make_proxy_node(ret);
            if( self->extra != NULL ) {
                RETVAL->extra = self->extra ;
                SvREFCNT_inc(self->extra);                
            }
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

ProxyObject *
getNextSibling( elem )
        ProxyObject* elem
    ALIAS:
        XML::LibXML::Node::nextSibling = 1
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr ret;
    CODE:
        ret = ((xmlNodePtr)elem->object)->next ;
        RETVAL = NULL;
        if ( ret ) {
            CLASS = domNodeTypeName( ret );
            RETVAL = make_proxy_node(ret);
            if( elem->extra != NULL ) {
                RETVAL->extra = elem->extra ;
                SvREFCNT_inc(elem->extra);                
            }
        }	
    OUTPUT:
        RETVAL

ProxyObject *
getPreviousSibling( elem )
        ProxyObject* elem
    ALIAS:
        XML::LibXML::Node::previousSibling = 1
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr ret;
    CODE:
        ret = ((xmlNodePtr)elem->object)->prev;
        RETVAL = NULL;
        if ( ret != NULL ) {
            CLASS = domNodeTypeName( ret );
            RETVAL = make_proxy_node(ret);
            if( elem->extra != NULL ) {
                RETVAL->extra = elem->extra ;
                SvREFCNT_inc(elem->extra);                
            }
        }
    OUTPUT:
        RETVAL

ProxyObject *
getFirstChild( elem )
        ProxyObject* elem
    ALIAS:
        XML::LibXML::Node::firstChild = 1
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr ret;
    CODE:
        ret = ((xmlNodePtr)elem->object)->children;
        RETVAL = NULL;
        if ( ret ) {
            CLASS = domNodeTypeName( ret );
            RETVAL = make_proxy_node(ret);
            if( elem->extra != NULL ) {
                RETVAL->extra = elem->extra;
                SvREFCNT_inc(elem->extra);
            }
        }
    OUTPUT:
        RETVAL


ProxyObject *
getLastChild( elem )
        ProxyObject* elem
    ALIAS:
        XML::LibXML::Node::lastChild = 1
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr ret;
    CODE:
        ret = ((xmlNodePtr)elem->object)->last;
        RETVAL = NULL;
        if ( ret ) {
            CLASS = domNodeTypeName( ret );
            RETVAL = make_proxy_node(ret);
            if( elem->extra != NULL ) {
                RETVAL->extra = elem->extra;
                SvREFCNT_inc(elem->extra);
            }
        }
    OUTPUT:
        RETVAL


void
insertBefore( self, new, ref ) 
        ProxyObject* self
        ProxyObject* new
        xmlNodePtr ref
    PREINIT:
        ProxyObject* pproxy= NULL;
        ProxyObject* cproxy= NULL; 
    CODE:
        if ( !(((xmlNodePtr)self->object)->type == XML_DOCUMENT_NODE
             && ((xmlNodePtr)new->object)->type == XML_ELEMENT_NODE ) 
             && domInsertBefore( self->object, new->object, ref ) != NULL ) {
            if ( ((xmlNodePtr)self->object)->type == XML_DOCUMENT_NODE ) {
                pproxy = self;
            }
            else if ( self->extra != NULL ){
                pproxy = (ProxyObject*)SvIV((SV*)SvRV(self->extra));
            }
            if ( new->extra != NULL ) {
                cproxy = (ProxyObject*)SvIV((SV*)SvRV(new->extra));
            }
            if ( pproxy->object != cproxy->object ) {
      
                # warn("different documents");
                if ( new->extra != NULL ){
                    # warn("decrease old child document");   
                    SvREFCNT_dec(new->extra);
                }

                new->extra = self->extra;

                if ( new->extra != NULL ){
                    #warn("increase child document");   
                    SvREFCNT_inc(new->extra);
                }
            }
        }


void
insertAfter( self, new, ref )
        ProxyObject* self
        ProxyObject* new
        xmlNodePtr ref
    PREINIT:
        ProxyObject* pproxy= NULL;
        ProxyObject* cproxy= NULL; 
    CODE:
        if ( !(((xmlNodePtr)self->object)->type == XML_DOCUMENT_NODE
             && ((xmlNodePtr)new->object)->type == XML_ELEMENT_NODE ) 
             && domInsertAfter( self->object, new->object, ref ) != NULL ) {
            if ( ((xmlNodePtr)self->object)->type == XML_DOCUMENT_NODE ) {
                pproxy = self;
            }
            else if ( self->extra != NULL ){
                pproxy = (ProxyObject*)SvIV((SV*)SvRV(self->extra));
            }
            if ( new->extra != NULL ) {
                cproxy = (ProxyObject*)SvIV((SV*)SvRV(new->extra));
            }
            if ( pproxy == NULL || 
                 cproxy == NULL || 
                 pproxy->object != cproxy->object ) {
      
                # warn("different documents");
                if ( new->extra != NULL ){
                    # warn("decrease child documents");   
                    SvREFCNT_dec(new->extra);
                }
    
                new->extra = self->extra;

                if ( new->extra != NULL ){
                    # warn("increase child documents");   
                    SvREFCNT_inc(new->extra);
                }
            }
        }

SV*
getOwnerDocument( elem )
        ProxyObject* elem
    ALIAS:
        XML::LibXML::Node::ownerDocument = 1
    CODE:
        RETVAL = &PL_sv_undef;
        if( ((xmlNodePtr)elem->object)->doc != NULL && elem->extra != NULL ){
            RETVAL = elem->extra;
            SvREFCNT_inc( RETVAL );
        }
    OUTPUT:
        RETVAL

SV*
getOwner( elem ) 
        ProxyObject * elem
    CODE:
        RETVAL = &PL_sv_undef;
        if( elem->extra != NULL ){
            RETVAL = elem->extra;
            SvREFCNT_inc( RETVAL );
        }
    OUTPUT:
        RETVAL

void
setOwnerDocument( elem, doc )
        ProxyObject* elem
        ProxyObject* doc
    PREINIT:
        xmlDocPtr real_doc;
    CODE:
        real_doc = (xmlDocPtr)doc->object;
        domSetOwnerDocument( elem->object, real_doc );
        SvREFCNT_inc( doc->extra );

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
            RETVAL = newSVpvn( (char *)name, xmlStrlen( name ) );
            xmlFree( name );
        }
        else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

void
setName( node , value )
        xmlNodePtr node
        char * value
    CODE:
        domSetName( node, value );

SV*
getData( proxy_node ) 
        ProxyObject * proxy_node 
    ALIAS:
        XML::LibXML::Attr::value     = 1
        XML::LibXML::Node::nodeValue = 2
        XML::LibXML::Attr::getValue  = 3
    PREINIT:
        xmlNodePtr node;
        char * content;
    CODE:
        node = (xmlNodePtr) proxy_node->object; 

        if( node != NULL ) {
            if ( node->type != XML_ATTRIBUTE_NODE ){
                if ( node->doc != NULL ){
                    content = domDecodeString( node->doc->encoding,
                                               node->content );
                }
                else {
                    content = xmlStrdup(node->content);
                }
            }
            else if ( node->children != NULL ) {
                if ( node->doc != NULL ){
                    content = domDecodeString( node->doc->encoding,
                                               node->children->content );
                }
                else {
                    content = xmlStrdup(node->children->content);
                }
            }
        }

        if ( content != NULL ){
            RETVAL = newSVpvn( (char *)content, xmlStrlen( content ) );
            xmlFree( content );
        }
        else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL


void
_findnodes( node, xpath )
        ProxyObject* node
        char * xpath 
    PREINIT:
        xmlNodeSetPtr nodelist = NULL;
        SV * element = NULL ;
        int len = 0 ;
    PPCODE:
        nodelist = domXPathSelect( node->object, xpath );
        if ( nodelist && nodelist->nodeNr > 0 ) {
            int i = 0 ;
            const char * cls = "XML::LibXML::Node";
            xmlNodePtr tnode;
            ProxyObject * proxy;
            
            len = nodelist->nodeNr;
            for( i ; i < len; i++){
               /* we have to create a new instance of an objectptr. and then 
                 * place the current node into the new object. afterwards we can 
                 * push the object to the array!
                 */
                element = NULL;
                tnode = nodelist->nodeTab[i];
                element = sv_newmortal();
                cls = domNodeTypeName( tnode );

                if (tnode->type == XML_NAMESPACE_DECL) {
                    element = sv_setref_pv( element, (char *)cls, (void*)tnode );
                } else {
                    proxy = make_proxy_node(tnode);
                    if ( node->extra != NULL ) {
                        proxy->extra = node->extra;
                        SvREFCNT_inc(node->extra);
                    }
                    element = sv_setref_pv( element, (char *)cls, (void*)proxy );
                }
                XPUSHs( element );
            }
            
            xmlXPathFreeNodeSet( nodelist );
        }

void
_find ( node, xpath )
        ProxyObject* node
        char * xpath
    PREINIT:
        xmlXPathObjectPtr found = NULL;
        xmlNodeSetPtr nodelist = NULL;
        SV * element = NULL ;
        int len = 0 ;
    PPCODE:
        found = domXPathFind( node->object, xpath );
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
                    ProxyObject * proxy;
                    SV * element;
                    
                    len = nodelist->nodeNr;
                    for( i ; i < len; i++){
                       /* we have to create a new instance of an objectptr. and then 
                         * place the current node into the new object. afterwards we can 
                         * push the object to the array!
                         */
                        element = NULL;
                        tnode = nodelist->nodeTab[i];
                        element = sv_newmortal();
                        cls = domNodeTypeName( tnode );
        
                        proxy = make_proxy_node(tnode);
                        if ( node->extra != NULL
                             && ((xmlNodePtr)node->object)->type != XML_DOCUMENT_NODE ) {
                            proxy->extra = node->extra;
                            SvREFCNT_inc(node->extra);
                        }
                
                        element = sv_setref_pv( element, (char *)cls, (void*)proxy );
                        cls = domNodeTypeName( tnode );
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
                croak("Uknown XPath return type");
        }
        xmlXPathFreeObject(found);

void
getChildnodes( node )
        ProxyObject* node
    ALIAS:
        XML::LibXML::Node::childNodes = 1
    PREINIT:
        xmlNodePtr cld;
        SV * element;
        int len = 0;
        const char * cls = "XML::LibXML::Node";
        ProxyObject * proxy;
        int wantarray = GIMME_V;
    PPCODE:
        cld = ((xmlNodePtr)node->object)->children;
        while ( cld ) {
            if( wantarray != G_SCALAR ) {
	            element = sv_newmortal();
                cls = domNodeTypeName( cld );
                proxy = make_proxy_node(cld);
                if ( node->extra != NULL ) {
                    proxy->extra = node->extra;
                    SvREFCNT_inc(node->extra);
                }
                element = sv_setref_pv( element, (char *)cls, (void*)proxy );
                XPUSHs( element );
            }
            cld = cld->next;
            len++;
        }
        if ( wantarray == G_SCALAR ) {
            XPUSHs( newSViv(len) );
        }

SV*
toString( self )
        xmlNodePtr self
    PREINIT:
        xmlBufferPtr buffer;
        char *ret = NULL;
    CODE:
        buffer = xmlBufferCreate();
        xmlNodeDump( buffer, self->doc, self, 0, 0 );
        if ( buffer->content != 0 ) {
            ret= xmlStrdup( buffer->content );
            # warn( "x -> %s\n", ret );
        }
        xmlBufferFree( buffer );
        
        if ( self->doc != NULL ) {
            xmlChar *retDecoded = domDecodeString( self->doc->encoding, ret );
            xmlFree( ret );
            ret= retDecoded;
        }

        if ( ret != NULL ) {
            RETVAL = newSVpvn( ret , strlen( ret ) ) ;
            xmlFree( ret );
        }
        else {
	        # warn("Failed to convert doc to string");           
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

int 
isEqual( self, other )
        xmlNodePtr self
        xmlNodePtr other
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
            if ( node->doc != NULL ) {
                lname = domDecodeString( node->doc->encoding, node->name );
            }
            else {
                lname = xmlStrdup( node->name );
            }
            RETVAL = newSVpvn( (char *)lname, xmlStrlen( lname ) );
            xmlFree( lname );
        }
        else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

SV*
getPrefix( node )
        xmlNodePtr node
    ALIAS:
        XML::LibXML::Node::prefix = 1
    PREINIT:
        char * prefix;
    CODE:
        if( node != NULL 
            && node->ns != NULL
            && node->ns->prefix != NULL ) {
            if ( node->doc != NULL ) {
                prefix = domDecodeString( node->doc->encoding, 
                                          node->ns->prefix );
            }
            else {
                prefix =  xmlStrdup( node->ns->prefix );
            }

            RETVAL = newSVpvn( (char *)prefix, xmlStrlen( prefix ) );
            xmlFree( prefix );
        }
        else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

SV*
getNamespaceURI( node )
        xmlNodePtr node
    PREINIT:
        const char * nsURI;
    CODE:
        if( node != NULL
            && node->ns != NULL
            && node->ns->href != NULL ) {
            nsURI =  node->ns->href;
            RETVAL = newSVpvn( (char *)nsURI, xmlStrlen( nsURI ) );
        }
        else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

int 
hasAttributes( node ) 
        ProxyObject * node
    CODE:
        RETVAL = 0;
        if( ((xmlNodePtr)node->object)->type == 1 
            ||((xmlNodePtr)node->object)->type == 7
            ||((xmlNodePtr)node->object)->type >= 9 ) {
            if( ((xmlNodePtr)node->object)->properties != NULL ) {
                RETVAL = 1;
            }
        }
    OUTPUT:
        RETVAL

void
getAttributes( node )
        ProxyObject* node
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
        real_node = (xmlNodePtr) node->object;

        attr      = real_node->properties;
        while ( attr != NULL ) {
            ProxyObject * proxy=NULL;
            if ( wantarray != G_SCALAR ) {
                element = sv_newmortal();   
                proxy = make_proxy_node((xmlNodePtr)attr);
                if ( node->extra != NULL ) {
                    proxy->extra = node->extra;
                    SvREFCNT_inc(node->extra);
                }
                XPUSHs( sv_setref_pv( element, (char *)CLASS, (void*)proxy ) );
            }
            attr = attr->next;
            len++;
        }
        ns = real_node->nsDef;
        while ( ns != NULL ) {
            const char * CLASS = "XML::LibXML::Namespace";
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
getAttributesNS( node,nsURI )
        ProxyObject* node
        char * nsURI
    PREINIT:
        xmlAttrPtr attr = NULL;
        xmlNodePtr real_node = NULL;
        SV * element;
        int len = 0;
        const char * CLASS = "XML::LibXML::Attr";
        int wantarray = GIMME_V;
    PPCODE:
        real_node = (xmlNodePtr) node->object;

        attr      = real_node->properties;
        while ( attr != NULL ) {
            if( attr->ns != NULL && xmlStrcmp( nsURI, attr->ns->href ) == 0 ){ 
                ProxyObject * proxy;
                if( wantarray != G_SCALAR ) {
                    element = sv_newmortal();
                    
                    proxy = make_proxy_node((xmlNodePtr)attr);
                    if ( node->extra != NULL ) {
                        proxy->extra = node->extra;
                        SvREFCNT_inc(node->extra);
                    }
                    XPUSHs( sv_setref_pv( element, (char *)CLASS, (void*)proxy ) );
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
getNamespace ( node, prefix )
        xmlNodePtr node
        char * prefix
    PREINIT:
        xmlNsPtr ns = NULL;
        const char * CLASS = "XML::LibXML::Namespace";
        SV * element;
    PPCODE:
        ns = node->nsDef;
        while ( ns != NULL ) {
            if (ns->prefix != NULL) {
                if (strcmp(prefix, ns->prefix) == 0) {
                    element = sv_newmortal();
                    XPUSHs( sv_setref_pv( element, (char *)CLASS, (void*)ns ) );
                    break;
                }
            } else {
                if (strlen(prefix) == 0) {
                    element = sv_newmortal();
                    XPUSHs( sv_setref_pv( element, (char *)CLASS, (void*)ns ) );
                    break;
                }
            }
            ns = ns->next;
        }

char *
string_value ( node )
        xmlNodePtr node
    ALIAS:
        to_literal = 1
    CODE:
        RETVAL = xmlXPathCastNodeToString(node);
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

ProxyObject *
new(CLASS, name )
        char * CLASS
        char * name
    PREINIT:
        xmlNodePtr newNode;
    CODE:
        # CLASS = "XML::LibXML::Element";
        newNode = xmlNewNode( 0, name );
        if( newNode != NULL ) {
            # init the keeping fragment
            xmlNodePtr docfrag = NULL;
            ProxyObject * dfProxy = NULL; 
            SV * docfrag_sv = NULL;

            docfrag = xmlNewDocFragment(NULL);
            dfProxy = make_proxy_node( docfrag );

            docfrag_sv = sv_newmortal(); 
            sv_setref_pv( docfrag_sv, 
                          "XML::LibXML::DocumentFragment", 
                          (void*)dfProxy );
            dfProxy->extra = docfrag_sv;
            # SvREFCNT_inc(docfrag_sv);
            # warn( "NEW FRAGMENT ELEMENT(%s)",name);
         
            newNode->next     = 0;
            newNode->prev     = 0;
            newNode->children = 0 ;
            newNode->last     = 0;
            newNode->doc      = 0;

            domAppendChild( docfrag, newNode );            

            RETVAL = make_proxy_node(newNode);
            RETVAL->extra = docfrag_sv;
            SvREFCNT_inc(docfrag_sv);
        }
    OUTPUT:
        RETVAL

void
setAttribute( elem, name, value )
        xmlNodePtr elem	
        char * name
        char * value
    CODE:
        if( elem->doc != NULL ) {
            name  = domEncodeString( elem->doc->encoding, name );
            value = domEncodeString( elem->doc->encoding, value );
        }
        xmlSetProp( elem, name, value );
        if ( elem->doc != NULL ) {
            xmlFree( name );
            xmlFree( value );
        }

void
setAttributeNS( elem, nsURI, qname, value )
        xmlNodePtr elem
        char * nsURI
        char * qname
        char * value
    PREINIT:
        xmlChar *prefix;
        xmlChar *lname = NULL;
        xmlNsPtr ns = NULL;
    CODE:
        if( elem->doc != NULL ) {
            qname = domEncodeString( elem->doc->encoding, qname );
            value = domEncodeString( elem->doc->encoding, value );
        }
    
        if ( nsURI != NULL && strlen(nsURI) != 0 ) {
            lname = xmlSplitQName2(qname, &prefix);
        
            ns = domNewNs (elem , prefix , nsURI);
            xmlSetNsProp( elem, ns, lname, value );
        }
        else {
            xmlSetProp( elem, qname, value );
        }

        if ( elem->doc != NULL ) {
            xmlFree( qname );
            xmlFree( value );
        }

ProxyObject *
setAttributeNode( elem, attrnode ) 
        ProxyObject* elem
        ProxyObject* attrnode 
    PREINIT:
        const char * CLASS = "XML::LibXML::Attr";
    CODE:
        RETVAL = make_proxy_node( (xmlNodePtr)domSetAttributeNode( (xmlNodePtr) elem->object, (xmlAttrPtr) attrnode->object ) );
        if ( elem->extra != NULL ) {
            RETVAL->extra = elem->extra;
            SvREFCNT_inc(elem->extra);
        }
    OUTPUT:
        RETVAL

int 
hasAttribute( elem, name ) 
        xmlNodePtr elem
        char * name
    PREINIT:
        xmlAttrPtr att = NULL;
    CODE:
        /**
         * xmlHasProp() returns the attribute node, which is not exactly what 
         * we want as a boolean value 
         **/
        att = xmlHasProp( elem, name );
        RETVAL = att == NULL ? 0 : 1 ;
    OUTPUT:
        RETVAL

int 
hasAttributeNS( elem, nsURI, name ) 
        xmlNodePtr elem
        char * nsURI
        char * name
    PREINIT:
        xmlAttrPtr att = NULL;
    CODE:
        /**
         * domHasNsProp() returns the attribute node, which is not exactly what 
         * we want as a boolean value 
         **/
        att = domHasNsProp( elem, name, nsURI );
        RETVAL = att == NULL ? 0 : 1 ;
    OUTPUT:
        RETVAL

SV*
getAttribute( elem, name ) 
        ProxyObject* elem
        char * name 
    PREINIT:
	    char * content = NULL;
    CODE:
        content = xmlGetProp( elem->object, name );
        if ( content != NULL ) {
            if ( ((xmlNodePtr)elem->object)->doc != NULL ){
                xmlChar* deccontent = domDecodeString( ((xmlNodePtr)elem->object)->doc->encoding, content );
               xmlFree( content);
               content = deccontent;
            }

            RETVAL  = newSVpvn( content, xmlStrlen( content ) );
            xmlFree( content );
        }
        else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

SV*
getAttributeNS( elem, nsURI ,name ) 
        ProxyObject* elem
        char * nsURI
        char * name 
    PREINIT:
        xmlAttrPtr att;
	    char * content = NULL;
    CODE:
        att = domHasNsProp( elem->object, name, nsURI );
        if ( att != NULL && att->children != NULL ) {
            content = xmlStrdup( att->children->content ); 
        }
        if ( content != NULL ) {
            if ( ((xmlNodePtr)elem->object)->doc != NULL ){
                xmlChar *deccontent = domDecodeString( ((xmlNodePtr)elem->object)->doc->encoding, content );
                xmlFree( content );
                content = deccontent;
            }

            RETVAL  = newSVpvn( content, xmlStrlen( content ) );
            xmlFree( content );
        }
        else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL


ProxyObject *
getAttributeNode( elemobj, name )
        ProxyObject * elemobj
        char * name
    PREINIT:
        const char * CLASS = "XML::LibXML::Attr";
        xmlNodePtr elem;
        xmlAttrPtr attrnode = NULL;
    CODE:
        elem = (xmlNodePtr) elemobj->object;
        RETVAL = NULL;
        attrnode = xmlHasProp( elem, name );
        if ( attrnode != NULL ) {
            RETVAL = make_proxy_node((xmlNodePtr)attrnode);
            if ( elemobj->extra != NULL ){
                RETVAL->extra = elemobj->extra;
                SvREFCNT_inc(elemobj->extra);
            }
        }
    OUTPUT:
        RETVAL

ProxyObject *
getAttributeNodeNS( elemobj, nsURI, name )
        ProxyObject* elemobj 
        char * nsURI
        char * name
    PREINIT:
        const char * CLASS = "XML::LibXML::Attr";
        xmlNodePtr elem;
        xmlAttrPtr attrnode = NULL;
    CODE:
        elem = (xmlNodePtr) elemobj->object;
        RETVAL = NULL;
        attrnode = domHasNsProp( elem, name, nsURI );
        if ( attrnode != NULL ) {
            RETVAL = make_proxy_node((xmlNodePtr)attrnode);
            if ( elemobj->extra != NULL ) {
                RETVAL->extra = elemobj->extra;
                SvREFCNT_inc(elemobj->extra);
            }
        }
    OUTPUT:
        RETVAL

void
removeAttribute( elem, name ) 	
        xmlNodePtr elem
        char * name
    CODE:
        xmlRemoveProp( xmlHasProp( elem, name ) );	

void
removeAttributeNS( elem, nsURI, name )
        xmlNodePtr elem
        char * nsURI
        char * name
    PREINIT:
        xmlChar *prefix;
        xmlChar *lname = NULL;
        xmlNsPtr ns = NULL;
    CODE:
        lname = xmlSplitQName2(name, &prefix);
        if (lname == NULL) /* as it is supposed to be */
            lname = name;
        /* ignore the given prefix if any, and use whatever
           is defined in scope for this nsURI */
        ns = xmlSearchNsByHref(elem->doc, elem, nsURI);
        xmlUnsetNsProp( elem, ns, lname );

void
getChildrenByTagName( elem, name )
        ProxyObject* elem
        char * name 
    PREINIT:
        xmlNodeSetPtr nodelist;
        SV * element;
        int len = 0;
        int wantarray = GIMME_V;
    PPCODE:
        nodelist = domGetElementsByTagName( elem->object , name );
        if ( nodelist && nodelist->nodeNr > 0 ) {
            int i = 0 ;
            const char * cls = "XML::LibXML::Node";
            xmlNodePtr tnode;
            ProxyObject * proxy;

            len = nodelist->nodeNr;
            if( wantarray == G_ARRAY ) {
                for( i ; i < len; i++){
                /* we have to create a new instance of an objectptr. and then 
                 * place the current node into the new object. afterwards we can 
                 * push the object to the array!
                 */
                    element = 0;
                    tnode = nodelist->nodeTab[i];
                    element = sv_newmortal();
                
                    proxy = make_proxy_node(tnode);
                    if ( elem->extra != NULL ) {
                        proxy->extra = elem->extra;
                        SvREFCNT_inc(elem->extra);
                    }
                    cls = domNodeTypeName( tnode );
                    XPUSHs( sv_setref_pv( element, (char *)cls, (void*)proxy ) );
                }
            }
            else {
                XPUSHs( newSViv( len ) );
            }
            xmlXPathFreeNodeSet( nodelist );
        }

void
getChildrenByTagNameNS( node, nsURI, name )
        ProxyObject* node
        char * nsURI
        char * name 
    PREINIT:
        xmlNodeSetPtr nodelist;
        SV * element;
        int len = 0;
        int wantarray = GIMME_V;
    PPCODE:
        nodelist = domGetElementsByTagNameNS( node->object , nsURI , name );
        if ( nodelist && nodelist->nodeNr > 0 ) {
            int i = 0 ;
            const char * cls = "XML::LibXML::Node";
            xmlNodePtr tnode;
            ProxyObject * proxy;

            len = nodelist->nodeNr;
            if( wantarray == G_ARRAY ) {
                for( i ; i < len; i++){
                /* we have to create a new instance of an objectptr. and then 
                 * place the current node into the new object. afterwards we can 
                 * push the object to the array!
                 */
                    element = 0;
                    tnode = nodelist->nodeTab[i];
                    element = sv_newmortal();
                
                    proxy = make_proxy_node(tnode);
                    if ( node->extra != NULL ) {
                        proxy->extra = node->extra;
                        SvREFCNT_inc(node->extra);
                    }

                    cls = domNodeTypeName( tnode );
                    XPUSHs( sv_setref_pv( element, (char *)cls, (void*)proxy ) );
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
        char * chunk
    PREINIT:
        xmlNodePtr rv;
    CODE:
        if( self->doc != NULL ) {
            chunk = domEncodeString( self->doc->encoding, chunk );
        }
        LibXML_error = sv_2mortal(newSVpv("", 0));
        rv = domReadWellBalancedString( self->doc, chunk );
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();

        if ( rv != NULL ) {
            xmlAddChildList( self , rv );
        }	
        if( chunk != NULL )
            xmlFree( chunk );

void 
appendTextNode( self, xmlString )
        xmlNodePtr self
        char * xmlString
    ALIAS:
        XML::LibXML::Element::appendText = 1
    PREINIT: 
        xmlNodePtr tn;
    CODE:
        if ( self->doc != NULL && xmlString != NULL ) {
            if ( self->doc != NULL ) {
                xmlString = domEncodeString( self->doc->encoding, xmlString );
                tn = xmlNewDocText( self->doc, xmlString ); 
                xmlFree(xmlString);
            }
            else {
                /* this for people working directly with UTF8 */
                tn = xmlNewText( xmlString );
            }
            domAppendChild( self, tn );
        }

void 
appendTextChild( self, childname, xmlString )
        xmlNodePtr self
        char * childname
        char * xmlString
    PREINIT:
        xmlChar * encname = NULL;
        xmlChar * enccontent= NULL;
    CODE:
        if( self->doc != NULL ) {
            childname = domEncodeString( self->doc->encoding, childname );
            xmlString = domEncodeString( self->doc->encoding, xmlString );
        }
        xmlNewTextChild( self, NULL, childname, xmlString );
        if (self->doc != NULL) {
            xmlFree(childname);
            xmlFree(xmlString);
        }

MODULE = XML::LibXML         PACKAGE = XML::LibXML::PI

void
_setData( node, value )
        xmlNodePtr node
        char * value
    CODE:
        domSetNodeValue(node,domEncodeString(node->doc->encoding,value));

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Text

void
setData( node, value )
        xmlNodePtr node
        char * value
    ALIAS:
        XML::LibXML::Attr::setValue = 1 
    CODE:
        if ( node->doc != NULL ) {
            value = domEncodeString( node->doc->encoding, value );
            # encode the entities
            value = xmlEncodeEntitiesReentrant( node->doc, value );
        }
        domSetNodeValue( node, value );

ProxyObject *
new( CLASS, content )
        const char * CLASS
        char * content
    PREINIT:
        xmlNodePtr newNode;
    CODE:
        /* we should test if this is UTF8 ... because this WILL cause
         * problems with iso encoded strings :(
         */
        newNode = xmlNewText( content );
        if( newNode != NULL ) {
            # init the keeping fragment
            xmlNodePtr docfrag = NULL;
            ProxyObject * dfProxy = NULL; 
            SV * docfrag_sv = NULL;

            docfrag = xmlNewDocFragment(NULL);
            dfProxy = make_proxy_node( docfrag );

            docfrag_sv = sv_newmortal(); 
            sv_setref_pv( docfrag_sv, 
                          "XML::LibXML::DocumentFragment", 
                          (void*)dfProxy );
            dfProxy->extra = docfrag_sv;
            # warn( "NEW FRAGMENT TEXT");
            # SvREFCNT_inc(docfrag_sv);
                     
            domAppendChild( docfrag, newNode );            

            RETVAL = make_proxy_node(newNode);
            RETVAL->extra = docfrag_sv;
            SvREFCNT_inc(docfrag_sv);
        }
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Comment

ProxyObject *
new( CLASS, content ) 
        const char * CLASS
        char * content
    PREINIT:
        xmlNodePtr newNode;
    CODE:
        newNode = xmlNewComment( content );
        if( newNode != NULL ) {
            # init the keeping fragment
            xmlNodePtr docfrag = NULL;
            ProxyObject * dfProxy = NULL; 
            SV * docfrag_sv = NULL;

            docfrag = xmlNewDocFragment(NULL);
            dfProxy = make_proxy_node( docfrag );

            docfrag_sv = sv_newmortal(); 
            sv_setref_pv( docfrag_sv, 
                          "XML::LibXML::DocumentFragment", 
                          (void*)dfProxy );
            dfProxy->extra = docfrag_sv;
            # warn( "NEW FRAGMENT COMMENT");
            # SvREFCNT_inc(docfrag_sv);
                     
            domAppendChild( docfrag, newNode );            

            RETVAL = make_proxy_node(newNode);
            RETVAL->extra = docfrag_sv;
            SvREFCNT_inc(docfrag_sv);
        }
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::CDATASection

ProxyObject *
new( CLASS , content )
        const char * CLASS
        char * content
    PREINIT:
        xmlNodePtr newNode;
    CODE:
        RETVAL = NULL;
        newNode = xmlNewCDataBlock( 0 , content, xmlStrlen( content ) );
        if ( newNode != NULL ){
            # init the keeping fragment
            xmlNodePtr docfrag = NULL;
            ProxyObject * dfProxy = NULL; 
            SV * docfrag_sv = NULL;

            docfrag = xmlNewDocFragment(NULL);
            dfProxy = make_proxy_node( docfrag );

            docfrag_sv = sv_newmortal(); 
            sv_setref_pv( docfrag_sv, 
                          "XML::LibXML::DocumentFragment", 
                          (void*)dfProxy );
            dfProxy->extra = docfrag_sv;
            # warn( "NEW FRAGMENT CDATA");
            # SvREFCNT_inc(docfrag_sv);
            
            domAppendChild( docfrag, newNode );            

            RETVAL = make_proxy_node(newNode);
            RETVAL->extra = docfrag_sv;
            SvREFCNT_inc(docfrag_sv);            
        }
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Attr

ProxyObject *
new( CLASS , name="", value="" )
        char * CLASS
        char * name
        char * value
    PREINIT:
        xmlNodePtr attr = NULL;
    CODE:
        attr = (xmlNodePtr)xmlNewProp( NULL, name, value );
        if ( attr ) {
            RETVAL = make_proxy_node( attr );
        }
    OUTPUT:
        RETVAL

void
DESTROY(self)
        ProxyObject* self
    CODE:
        /* XXX free self->extra if refcnt self->extra == 0 */
        if ( (xmlNodePtr)self->object != NULL 
              && ((xmlNodePtr)self->object)->parent == NULL ) {
            ((xmlNodePtr)self->object)->doc =NULL;
            xmlFreeProp((xmlAttrPtr)self->object);            
            # warn( "REAL ATTRIBUTE DROPPED" );
        }
        # else {
            # warn("ATTRIBUTE IS BOUND");
        # }
        if( self->extra != NULL ) {
            SvREFCNT_dec(self->extra);
        }
        self->object = NULL;
        Safefree( self );

ProxyObject *
getOwnerElement( attrnode ) 
        ProxyObject * attrnode 
    ALIAS:
        XML::LibXML::Attr::ownerElement = 1
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr attr;
        xmlNodePtr parent;
    CODE:
        attr   = (xmlNodePtr) attrnode->object;
        parent = attr->parent;
        if ( parent ) {
            CLASS  = domNodeTypeName( parent );
            RETVAL = make_proxy_node(parent);
            if ( attrnode->extra != NULL ) {
                RETVAL->extra = attrnode->extra;
                SvREFCNT_inc(attrnode->extra); 
            }
        }
    OUTPUT:
        RETVAL

SV*
getParentElement( attrnode )
        ProxyObject * attrnode
    ALIAS:
        XML::LibXML::Attr::parentNode = 1
    CODE:
        RETVAL = &PL_sv_undef;
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::DocumentFragment

void
_fix_extra(node_sv)
        SV * node_sv
    PREINIT:
        ProxyObject* node;
    CODE:
        node = (ProxyObject *)SvIV((SV*)SvRV(node_sv));
        node->extra = node_sv;

SV*
new( CLASS )
        char * CLASS
    PREINIT:
        SV * frag_sv = NULL;
        xmlNodePtr real_dom=NULL;
        ProxyObject * ret= NULL;
    CODE:
        real_dom = xmlNewDocFragment( NULL ); 
        ret = make_proxy_node( real_dom );
        RETVAL = sv_newmortal();
        sv_setref_pv( RETVAL, (char *)CLASS, (void*)ret );
        ret->extra = RETVAL;
        # warn( "NEW FRAGMENT FORCE NEW");
        SvREFCNT_inc(RETVAL);
        /* double incrementation needed here */
        SvREFCNT_inc(RETVAL);
    OUTPUT:
        RETVAL

void
DESTROY(self)
        ProxyObject* self
    PREINIT:
        xmlNodePtr object;
    CODE:
        object = (xmlNodePtr)self->object;
        if ( object != NULL ) {
            # domSetOwnerDocument( (xmlNodePtr)self->object, NULL ); 
            # if( ((xmlNodePtr)self->object)->children !=NULL){
            #     warn("CLDNODES EXIST");
            #     warn(" --> %s \n", ((xmlNodePtr)self->object)->children->name );
            # }
            
            # warn("xmlFreeNode\n");
            xmlFreeNode(self->object);
            # warn( "REAL DOCUMENT FRAGMENT DROPPED" );
        }
        self->object = NULL;
        Safefree( self );

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
        
char *
prefix (self)
        xmlNsPtr self
    ALIAS:
        XML::LibXML::Namespace::getLocalName = 1
        XML::LibXML::Namespace::localName = 2
    CODE:
        RETVAL = (char*)self->prefix;
    OUTPUT:
        RETVAL


char *
getData (self)
        xmlNsPtr self
    ALIAS:
        XML::LibXML::Namespace::value = 1
        XML::LibXML::Namespace::getValue = 2
        XML::LibXML::Namespace::uri = 3
    CODE:
        RETVAL = (char*)self->href;
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
