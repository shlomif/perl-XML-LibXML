/* $Id$ */

#ifdef __cplusplus
extern "C" {
#endif

/* perl stuff */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include <fcntl.h>

#ifndef WIN32
#  include <unistd.h>
#endif

/* libxml2 stuff */
#include <libxml/xmlmemory.h>
#include <libxml/parser.h>
#include <libxml/parserInternals.h>
#include <libxml/HTMLparser.h>
#include <libxml/HTMLtree.h>
#include <libxml/DOCBparser.h>
#include <libxml/tree.h>
#include <libxml/xpath.h>
#include <libxml/xmlIO.h>
/* #include <libxml/debugXML.h> */
#include <libxml/xmlerror.h>
#include <libxml/xinclude.h>
#include <libxml/valid.h>
#include <libxml/catalog.h>

/* GDOME support
 * libgdome installs only the core functions to the system.
 * this is not enough for XML::LibXML <-> XML::GDOME conversion.
 * therefore there is the need to ship as well the GDOME core headers.
 */
#ifdef XML_LIBXML_GDOME_SUPPORT
#include <libgdome/gdome.h>
#include <libgdome/gdome-libxml-util.h>
#endif

/* XML::LibXML stuff */
#include "perl-libxml-mm.h"
#include "perl-libxml-sax.h"

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
LIBXML_DLL_IMPORT extern int xmlDoValidityCheckingDefaultValue;
LIBXML_DLL_IMPORT extern int xmlSubstituteEntitiesDefaultValue;
#endif
LIBXML_DLL_IMPORT extern int xmlGetWarningsDefaultValue;
LIBXML_DLL_IMPORT extern int xmlKeepBlanksDefaultValue;
LIBXML_DLL_IMPORT extern int xmlLoadExtDtdDefaultValue;
LIBXML_DLL_IMPORT extern int xmlPedanticParserDefaultValue;

#define TEST_PERL_FLAG(flag) \
    SvTRUE(perl_get_sv(flag, FALSE)) ? 1 : 0

static SV * LibXML_match_cb = NULL;
static SV * LibXML_read_cb  = NULL;
static SV * LibXML_open_cb  = NULL;
static SV * LibXML_close_cb = NULL;

static SV * LibXML_error    = NULL;

/* this should keep the default */
static xmlExternalEntityLoader LibXML_old_ext_ent_loader = NULL;

/* ****************************************************************
 * Error handler
 * **************************************************************** */

/* stores libxml errors into $@ */
void
LibXML_error_handler(void * ctxt, const char * msg, ...)
{
    va_list args;
    SV * sv;
    /* xmlParserCtxtPtr context = (xmlParserCtxtPtr) ctxt; */

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
    char * string = NULL;
    
    sv = NEWSV(0,512);
    
    va_start(args, msg);
    sv_vsetpvfn(sv, msg, strlen(msg), &args, NULL, 0, NULL);
    va_end(args);
    
    string = SvPV(sv, len);
    if ( string != NULL ) {
        if ( len > 0 ) {
             warn("validation error: '%s'" , string);
        }
        Safefree(string);
    }

    SvREFCNT_dec(sv);
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
        cnt = perl_call_method("read", G_SCALAR | G_EVAL);
    }
    else {
        cnt = perl_call_pv("__read", G_SCALAR | G_EVAL);
    }

    SPAGAIN;

    if (cnt != 1) {
        croak("read method call failed");
    }
    
    if (SvTRUE(ERRSV)) {
       STRLEN n_a;
       croak("read on filehandle failed: %s", SvPV(ERRSV, n_a));
       POPs ;
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

        dTHX;
        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 1);
        PUSHs(sv_2mortal(newSVpv((char*)filename, 0)));
        PUTBACK;

        count = perl_call_sv(callback, G_SCALAR | G_EVAL);

        SPAGAIN;
        
        if (count != 1) {
            croak("match callback must return a single value");
        }
        
        if (SvTRUE(ERRSV)) {
            STRLEN n_a;
       	    croak("input match callback died: %s", SvPV(ERRSV, n_a));
       	    POPs ;
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

        dTHX;
        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 1);
        PUSHs(sv_2mortal(newSVpv((char*)filename, 0)));
        PUTBACK;

        count = perl_call_sv(callback, G_SCALAR | G_EVAL);

        SPAGAIN;
        
        if (count != 1) {
            croak("open callback must return a single value");
        }

	if (SvTRUE(ERRSV)) {
            STRLEN n_a;
       	    croak("input callback died: %s", SvPV(ERRSV, n_a));
       	    POPs ;
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

        dTHX;
        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 2);
        PUSHs(ctxt);
        PUSHs(sv_2mortal(newSViv(len)));
        PUTBACK;

        count = perl_call_sv(callback, G_SCALAR | G_EVAL);

        SPAGAIN;
        
        if (count != 1) {
            croak("read callback must return a single value");
        }

        if (SvTRUE(ERRSV)) {
            STRLEN n_a;
       	    croak("read callback died: %s", SvPV(ERRSV, n_a));
       	    POPs ;
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

        dTHX;
        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 1);
        PUSHs(ctxt);
        PUTBACK;

        count = perl_call_sv(callback, G_SCALAR | G_EVAL);

        SPAGAIN;

        SvREFCNT_dec(ctxt);
        
        if (!count) {
            croak("close callback failed");
        }

        if (SvTRUE(ERRSV)) {
            STRLEN n_a;
       	    croak("close callback died: %s", SvPV(ERRSV, n_a));
       	    POPs ;
        }

        PUTBACK;
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

        int cnt; 
        SV * read_results;
        STRLEN read_length;
        char * chars;
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

        cnt = perl_call_pv("XML::LibXML::__write", G_SCALAR | G_EVAL);

        SPAGAIN;

        if (cnt != 1) {
            croak("write method call failed");
        }

        if (SvTRUE(ERRSV)) {
            STRLEN n_a;
       	    croak("write method call died: %s", SvPV(ERRSV, n_a));
       	    POPs ;
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
        dTHX;
        dSP;
        
        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;
        XPUSHs(sv_2mortal(newSVpv((char*)URL, 0)));
        XPUSHs(sv_2mortal(newSVpv((char*)ID, 0)));
        PUTBACK;
        
        count = perl_call_sv(*func, G_SCALAR | G_EVAL);
        
        SPAGAIN;
        
        if (!count) {
            croak("external entity handler did not return a value");
        }
        
        if (SvTRUE(ERRSV)) {
            STRLEN n_a;
       	    croak("external entity callback died: %s", SvPV(ERRSV, n_a));
       	    POPs ;
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

/* ****************************************************************
 * Helper functions
 * **************************************************************** */

void
LibXML_init_parser( SV * self ) {
    /* we fetch all switches and callbacks from the hash */
    SV** item    = NULL;
    SV*  item2   = NULL;

    xmlSetGenericErrorFunc(PerlIO_stderr(), 
                           (xmlGenericErrorFunc)LibXML_error_handler);

    if ( self != NULL ) {
        /* first fetch the values from the hash */
        HV* real_obj = (HV *)SvRV(self);
        SV * RETVAL  = NULL; /* dummy for the stupid macro */

        item = hv_fetch( real_obj, "XML_LIBXML_VALIDATION", 21, 0 );
        if ( item != NULL && SvTRUE(*item) ) {  
            xmlDoValidityCheckingDefaultValue = 1;
            xmlLoadExtDtdDefaultValue |= XML_DETECT_IDS;
        }
        else {
            xmlDoValidityCheckingDefaultValue = 0;
        }

        item = hv_fetch( real_obj, "XML_LIBXML_EXPAND_ENTITIES", 26, 0 );
        if ( item != NULL ) {
            if ( SvTRUE(*item) ) {
                xmlSubstituteEntitiesDefaultValue = 1;
                xmlLoadExtDtdDefaultValue |= XML_DETECT_IDS;
            }
            else {
                xmlSubstituteEntitiesDefaultValue = 0;
            }
        }
        else {
            xmlSubstituteEntitiesDefaultValue = 1;
            xmlLoadExtDtdDefaultValue |= XML_DETECT_IDS;
        }

        item = hv_fetch( real_obj, "XML_LIBXML_KEEP_BLANKS", 22, 0 );
        if ( item != NULL ) {
            if ( SvTRUE(*item) )
                xmlKeepBlanksDefault(1);
            else {
                xmlKeepBlanksDefault(0);
            }
        }
        else {
            /* keep blanks on default */
            xmlKeepBlanksDefault(1);
        }

        item = hv_fetch( real_obj, "XML_LIBXML_PEDANTIC", 19, 0 );
        xmlPedanticParserDefaultValue = item != NULL && SvTRUE(*item) ? 1 : 0;

        item = hv_fetch( real_obj, "XML_LIBXML_EXT_DTD", 18, 0 );
        if ( item != NULL && SvTRUE(*item) )
            xmlLoadExtDtdDefaultValue |= 1;
        else
            xmlLoadExtDtdDefaultValue ^= 1;

        item = hv_fetch( real_obj, "XML_LIBXML_COMPLETE_ATTR", 24, 0 );
        if (item != NULL && SvTRUE(*item)) {
            xmlLoadExtDtdDefaultValue |= XML_COMPLETE_ATTRS;
        }
        else {
            xmlLoadExtDtdDefaultValue ^= XML_COMPLETE_ATTRS;
        }
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

    /*
     * If the parser callbacks are not set, we have to check CLASS wide
     * callbacks.
     */
    if ( LibXML_match_cb == NULL ) {
        item2 = perl_get_sv("XML::LibXML::MatchCB", 0);
        if ( item != NULL  && SvTRUE(item2)) 
            LibXML_match_cb= item2;
    }
    if ( LibXML_read_cb == NULL ) {
        item2 = perl_get_sv("XML::LibXML::ReadCB", 0);
        if ( item2 != NULL  && SvTRUE(item2)) 
            LibXML_read_cb= item2;
    }
    if ( LibXML_open_cb == NULL ) {
        item2 = perl_get_sv("XML::LibXML::OpenCB", 0);
        if ( item2 != NULL  && SvTRUE(item2)) 
            LibXML_open_cb= item2;
    }
    if ( LibXML_close_cb == NULL ) {
        item2 = perl_get_sv("XML::LibXML::CloseCB", 0);
        if ( item2 != NULL  && SvTRUE(item2)) 
            LibXML_close_cb= item2;
    }


    LibXML_old_ext_ent_loader =  xmlGetExternalEntityLoader();
    xmlSetExternalEntityLoader( (xmlExternalEntityLoader)LibXML_load_external_entity );
    return; 

    xmlRegisterInputCallbacks((xmlInputMatchCallback) LibXML_input_match,
                              (xmlInputOpenCallback) LibXML_input_open,
                              (xmlInputReadCallback) LibXML_input_read,
                              (xmlInputCloseCallback) LibXML_input_close);



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
    xmlSetExternalEntityLoader( (xmlExternalEntityLoader)LibXML_old_ext_ent_loader );

}

void
LibXML_cleanup_callbacks() {
    
    return;
    xs_warn("      cleanup parser callbacks!\n"); 

    xmlCleanupInputCallbacks();
    xmlRegisterDefaultInputCallbacks();
/*    if ( LibXML_old_ext_ent_loader != NULL ) { */
/*        xmlSetExternalEntityLoader( NULL ); */
/*        xmlSetExternalEntityLoader( LibXML_old_ext_ent_loader ); */
/*        LibXML_old_ext_ent_loader = NULL; */
/*    } */
/*    xsltSetGenericDebugFunc(NULL, NULL); */

}

/* ****************************************************************
 * general parse functions 
 * **************************************************************** */

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

    if ( doc != NULL ) {
        if (
            !well_formed
            || ( xmlDoValidityCheckingDefaultValue
                 && !valid
                 && (doc->intSubset
                     || doc->extSubset) ) 
            ) {
            xmlFreeDoc(doc);
            return NULL;
        }

        /* this should be done by libxml2 !? */
        if (doc->encoding == NULL) {
            /*  *LEAK NOTE* i am not shure if this is correct */
            doc->encoding = xmlStrdup((const xmlChar*)"UTF-8");
        }

        if ( directory == NULL ) {
            STRLEN len;
            SV * newURI = sv_2mortal(newSVpvf("unknown-%12.12d", (void*)doc));
            doc->URL = xmlStrdup((const xmlChar*)SvPV(newURI, len));
        } else {
            doc->URL = xmlStrdup((const xmlChar*)directory);
        }
    }

    return doc;
}

void
LibXML_parse_sax_stream(SV * self, SV * ioref, char * directory)
{
    xmlParserCtxtPtr ctxt;
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
        ctxt = xmlCreatePushParserCtxt(PSaxGetHandler(),
                                       NULL,
                                       buffer,
                                       read_length,
                                       NULL);
        if (ctxt == NULL) {
            croak("Could not create push parser context: %s", strerror(errno));
        }
        ctxt->directory = directory;
        PmmSAXInitContext( ctxt, self );

        while(read_length = LibXML_read_perl(ioref, buffer, 1024)) {
            xmlParseChunk(ctxt, buffer, read_length, 0);
        }
        ret = xmlParseChunk(ctxt, buffer, 0, 1);

        ctxt->directory = NULL;

        xmlFree(ctxt->sax);
        ctxt->sax = NULL;
        PmmSAXCloseContext(ctxt);
        xmlFreeParserCtxt(ctxt);

    }
    else {
        croak( "Empty Stream" );
    }

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
        ctxt = htmlCreatePushParserCtxt(NULL, NULL, buffer, read_length,
                                        NULL, XML_CHAR_ENCODING_NONE);
        if (ctxt == NULL) {
            croak("Could not create html push parser context: %s",
                  strerror(errno));
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


xmlDocPtr
LibXML_parse_sgml_stream(SV * self, SV * ioref, SV * enc )
{
    xmlDocPtr doc = NULL;
    htmlParserCtxtPtr ctxt;
    int well_formed = 0;
    char buffer[1024];
    int read_length;
    int ret = -1;

    const xmlChar * encoding = Sv2C( enc, NULL );

    read_length = LibXML_read_perl(ioref, buffer, 4);
    if (read_length > 0) {
        ctxt = docbCreatePushParserCtxt(NULL, NULL, buffer, read_length,
                                        NULL,
                                        xmlParseCharEncoding( (const char*)encoding ));
        if (ctxt == NULL) {
            croak("Could not create sgml push parser context: %s",
                  strerror(errno));
        }

        ctxt->_private = (void*)self;

        while(read_length = LibXML_read_perl(ioref, buffer, 1024)) {
            ret = docbParseChunk(ctxt, buffer, read_length, 0);
            if ( ret != 0 ) {
                break;
            }   
        }
        ret = docbParseChunk(ctxt, buffer, 0, 1);

        if ( ret == 0 ) {
            doc = ctxt->myDoc;
            well_formed = ctxt->wellFormed;
            docbFreeParserCtxt(ctxt);
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

MODULE = XML::LibXML         PACKAGE = XML::LibXML

PROTOTYPES: DISABLE

BOOT:
    LIBXML_TEST_VERSION
    xmlInitParser();
    PmmSAXInitialize();

    /* make the callback mechnism available to perl coders */
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
        SV * CLASS 
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
        xmlParserCtxtPtr ctxt = NULL;
        STRLEN len;
        char * ptr;
        int well_formed;
        int valid;
        int ret;
        xmlDocPtr real_dom;
        HV* real_obj = (HV *)SvRV(self);
        SV** item    = NULL;
        int recover ;
    CODE:
        ptr = SvPV(string, len);
        if (len == 0) {
            croak("Empty string");
        }

        LibXML_init_parser(self);
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
        ret = xmlParseDocument(ctxt);

        # warn( "document parsed \n");

        ctxt->directory = NULL;

        well_formed = ctxt->wellFormed;
        valid = ctxt->valid;

        real_dom = ctxt->myDoc;
        xmlFreeParserCtxt(ctxt);

        sv_2mortal(LibXML_error);
        
        if ( real_dom == NULL ) {
            if ( SvCUR( LibXML_error ) > 0 ) {
                croak(SvPV(LibXML_error, len));
            }
            XSRETURN_UNDEF;
        }

        if ( directory == NULL ) {
            STRLEN len;
            SV * newURI = sv_2mortal(newSVpvf("unknown-%12.12d", (void*)real_dom));
            real_dom->URL = xmlStrdup((const xmlChar*)SvPV(newURI, len));
        } else {
            real_dom->URL = xmlStrdup((const xmlChar*)directory);
        }

        item = hv_fetch( real_obj, "XML_LIBXML_RECOVER", 18, 0 );
        recover = ( item != NULL && SvTRUE(*item) ) ? 1 : 0;
        if ( ( !well_formed && !recover )
               || (xmlDoValidityCheckingDefaultValue
                    && !valid && !recover 
                    && (real_dom->intSubset || real_dom->extSubset) ) ) {
            xmlFreeDoc(real_dom);
            RETVAL = &PL_sv_undef;    
            croak(SvPV(LibXML_error, len));
        }
        else if (xmlDoValidityCheckingDefaultValue
                 && SvCUR(LibXML_error) > 0
                 && (real_dom->intSubset || real_dom->extSubset) ) {
            croak(SvPV(LibXML_error, len));
        }
        else {
            item = hv_fetch( real_obj, "XML_LIBXML_GDOME", 16, 0 );

            if ( item != NULL && SvTRUE(*item) ) {  
                RETVAL = PmmNodeToGdomeSv( (xmlNodePtr)real_dom );
            }
            else {
                RETVAL = PmmNodeToSv((xmlNodePtr)real_dom, NULL);
            }
        }        
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser(); 
    OUTPUT:
        RETVAL

int
_parse_sax_string(self, string)
        SV * self
        SV * string
    PREINIT:
        xmlParserCtxtPtr ctxt;
        STRLEN len;
        char * ptr;
        int well_formed;
        int ret;
    INIT:
        ptr = SvPV(string, len);
        if (len == 0) {
            croak("Empty string");
            XSRETURN_UNDEF;
        }
    CODE:
        ctxt = xmlCreateMemoryParserCtxt(ptr, len);

        if (ctxt == NULL) {
            croak("Couldn't create memory parser context: %s", strerror(errno));
        }
        PmmSAXInitContext( ctxt, self );

        ctxt->sax = PSaxGetHandler();

        LibXML_init_parser(self);
        RETVAL = xmlParseDocument(ctxt);

        xmlFree( ctxt->sax );
        ctxt->sax = NULL;
        PmmSAXCloseContext(ctxt);
        xmlFreeParserCtxt(ctxt);

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
        STRLEN len;
        xmlDocPtr real_dom;
        HV* real_obj = (HV *)SvRV(self);
        SV** item    = NULL;
        int recover = 0;
    CODE:
        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);

        LibXML_init_parser(self);
        real_dom = LibXML_parse_stream(self, fh, directory);
        
        sv_2mortal(LibXML_error);

        item = hv_fetch( real_obj, "XML_LIBXML_RECOVER", 18, 0 );
        recover = ( item != NULL && SvTRUE( *item ) ) ? 1 : 0;

        if (real_dom == NULL) {
            if ( SvCUR( LibXML_error ) > 0 ) {
                croak(SvPV(LibXML_error, len));
            }
            XSRETURN_UNDEF;
        }
        else if (xmlDoValidityCheckingDefaultValue
                 && SvCUR(LibXML_error) > 0
                 && (real_dom->intSubset || real_dom->extSubset) 
                 && recover == 0 ) {
            croak(SvPV(LibXML_error, len));
        }
        else {
            item = hv_fetch( real_obj, "XML_LIBXML_GDOME", 16, 0 );

            if ( item != NULL && SvTRUE(*item) ) {  
                RETVAL = PmmNodeToGdomeSv( (xmlNodePtr)real_dom );
            }
            else {
                RETVAL = PmmNodeToSv((xmlNodePtr)real_dom, NULL);
            }
        }
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();
    OUTPUT:
        RETVAL

void
_parse_sax_fh(self, fh, directory = NULL)
        SV * self
        SV * fh
        char * directory
    PREINIT:
    CODE:  warn $@;
        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);

        LibXML_init_parser(self);
        LibXML_parse_sax_stream(self, fh, directory);
        
        sv_2mortal(LibXML_error);
        
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();

SV*
_parse_file(self, filename)
        SV * self
        const char * filename
    PREINIT:
        xmlParserCtxtPtr ctxt;
        int well_formed = 0;
        int valid = 0;
        STRLEN len;
        xmlDocPtr real_dom = NULL;
        HV* real_obj = (HV *)SvRV(self);
        SV** item    = NULL;
        int recover;
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
        valid       = ctxt->valid;

        real_dom = ctxt->myDoc;
        xmlFreeParserCtxt(ctxt);
        
        sv_2mortal(LibXML_error);
        
        if ( real_dom == NULL ) {
            if ( SvCUR( LibXML_error ) > 0 ) {
                croak(SvPV(LibXML_error, len));
            }
            XSRETURN_UNDEF;
        }

        item = hv_fetch( real_obj, "XML_LIBXML_RECOVER", 18, 0 );
        recover = ( item != NULL && SvTRUE(*item) ) ? 1 : 0;

        if (  ( !well_formed && !recover )
               || (xmlDoValidityCheckingDefaultValue
                   && !recover 
                   && (!valid
                       || SvCUR(LibXML_error) > 0 )
                   && (real_dom->intSubset
                       || real_dom->extSubset) )  ) {
            xmlFreeDoc(real_dom);
            croak("'%s'",SvPV(LibXML_error, len));
            XSRETURN_UNDEF;
        }
        else {
            item = hv_fetch( real_obj, "XML_LIBXML_GDOME", 16, 0 );

            if ( item != NULL && SvTRUE(*item) ) {  
                RETVAL = PmmNodeToGdomeSv( (xmlNodePtr)real_dom );
            }
            else {
                RETVAL = PmmNodeToSv((xmlNodePtr)real_dom, NULL);
            }
        }
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();
    OUTPUT:
        RETVAL

void
_parse_sax_file(self, filename)
        SV * self
        const char * filename
    PREINIT:
        xmlParserCtxtPtr ctxt;
        STRLEN len;
    CODE:
        LibXML_init_parser(self);
        ctxt = xmlCreateFileParserCtxt(filename);

        if (ctxt == NULL) {
            croak("Could not create file parser context for file '%s' : %s", filename, strerror(errno));
        }

        ctxt->sax = PSaxGetHandler();
        PmmSAXInitContext( ctxt, self );
        
        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);

        xmlParseDocument(ctxt);

        xmlFree(ctxt->sax);
        ctxt->sax = NULL;
        PmmSAXCloseContext(ctxt);
        xmlFreeParserCtxt(ctxt);
                
        sv_2mortal(LibXML_error);
        
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();

SV*
parse_html_string(self, string)
        SV * self
        SV * string
    PREINIT:
        htmlParserCtxtPtr ctxt;
        STRLEN len;
        char * ptr;
        int well_formed;
        int ret;
        xmlDocPtr real_dom;
        HV* real_obj = (HV *)SvRV(self);
        SV** item    = NULL;
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
        
        if (!real_dom) {
            if ( SvCUR( LibXML_error ) > 0 ) {
                croak(SvPV(LibXML_error, len));
            }
            XSRETURN_UNDEF;
        }
        else {
            STRLEN n_a;
            SV * newURI = newSVpvf("unknown-%12.12d", real_dom);
            real_dom->URL = xmlStrdup((const xmlChar*)SvPV(newURI, n_a));
            SvREFCNT_dec(newURI);

            item = hv_fetch( real_obj, "XML_LIBXML_GDOME", 16, 0 );            
            if ( item != NULL && SvTRUE(*item) ) {  
                RETVAL = PmmNodeToGdomeSv( (xmlNodePtr)real_dom );
            }
            else {
                RETVAL = PmmNodeToSv((xmlNodePtr)real_dom, NULL);
            }
        }
    OUTPUT:
        RETVAL

SV*
parse_html_fh(self, fh)
        SV * self
        SV * fh
    PREINIT:
        STRLEN len;
        xmlDocPtr real_dom;
        HV* real_obj = (HV *)SvRV(self);
        SV** item    = NULL;
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
            item = hv_fetch( real_obj, "XML_LIBXML_GDOME", 16, 0 );

            if ( item != NULL && SvTRUE(*item) ) {  
                RETVAL = PmmNodeToGdomeSv( (xmlNodePtr)real_dom );
            }
            else {
                RETVAL = PmmNodeToSv((xmlNodePtr)real_dom, NULL);
            }
        }
    OUTPUT:
        RETVAL
       
SV*
parse_html_file(self, filename)
        SV * self
        const char * filename
    PREINIT:
        STRLEN len;
        xmlDocPtr real_dom;
        HV* real_obj = (HV *)SvRV(self);
        SV** item    = NULL;
    CODE:
        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);
        
        LibXML_init_parser(self);
        real_dom = htmlParseFile((char*)filename, NULL);
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();

        sv_2mortal(LibXML_error);
        
        if (!real_dom) {
            if ( SvCUR( LibXML_error ) > 0 ) {
                croak(SvPV(LibXML_error, len));
            }
            XSRETURN_UNDEF;
        }
        else {
            item = hv_fetch( real_obj, "XML_LIBXML_GDOME", 16, 0 );

            if ( item != NULL && SvTRUE(*item) ) {  
                RETVAL = PmmNodeToGdomeSv( (xmlNodePtr)real_dom );
            }
            else {
                RETVAL = PmmNodeToSv((xmlNodePtr)real_dom, NULL);
            }
        }
    OUTPUT:
        RETVAL

SV*
parse_sgml_fh(self, fh, encoding)
        SV * self
        SV * fh
        SV * encoding
    PREINIT:
        STRLEN len;
        xmlDocPtr real_dom;
        HV* real_obj = (HV *)SvRV(self);
        SV** item    = NULL;
    CODE:
        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);
        
        LibXML_init_parser(self);
        real_dom = LibXML_parse_sgml_stream(self, fh, encoding);
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
            item = hv_fetch( real_obj, "XML_LIBXML_GDOME", 16, 0 );

            if ( item != NULL && SvTRUE(*item) ) {  
                RETVAL = PmmNodeToGdomeSv( (xmlNodePtr)real_dom );
            }
            else {
                RETVAL = PmmNodeToSv((xmlNodePtr)real_dom, NULL);
            }
        }
    OUTPUT:
        RETVAL

SV*
parse_sgml_string(self, string, encoding)
        SV * self
        SV * string
        SV * encoding
    PREINIT:
        htmlParserCtxtPtr ctxt;
        STRLEN len;
        char * ptr;
        int well_formed;
        int ret;
        xmlDocPtr real_dom;
        HV* real_obj = (HV *)SvRV(self);
        SV** item    = NULL;
    CODE:
        ptr = SvPV(string, len);
        if (len == 0) {
            croak("Empty string");
        }
        
        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);
        
        LibXML_init_parser(self);
        real_dom = (xmlDocPtr) docbParseDoc((xmlChar*)ptr,
                                            Sv2C(encoding, NULL));

        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();        

        sv_2mortal(LibXML_error);
        
        if (!real_dom) {
            if ( SvCUR( LibXML_error ) > 0 ) {
                croak(SvPV(LibXML_error, len));
            }
            XSRETURN_UNDEF;
        }
        else {
            STRLEN n_a;
            SV * newURI = newSVpvf("unknown-%12.12d", real_dom);
            real_dom->URL = xmlStrdup((const xmlChar*)SvPV(newURI, n_a));
            SvREFCNT_dec(newURI);

            item = hv_fetch( real_obj, "XML_LIBXML_GDOME", 16, 0 );            
            if ( item != NULL && SvTRUE(*item) ) {  
                RETVAL = PmmNodeToGdomeSv( (xmlNodePtr)real_dom );
            }
            else {
                RETVAL = PmmNodeToSv((xmlNodePtr)real_dom, NULL);
            }
        }
    OUTPUT:
        RETVAL

SV*
parse_sgml_file(self, fn, encoding)
        SV * self
        SV * fn
        SV * encoding
    PREINIT:
        const char * filename = (const char*)Sv2C( fn, NULL );
        STRLEN len;
        xmlDocPtr real_dom;
        HV* real_obj = (HV *)SvRV(self);
        SV** item    = NULL;
    CODE:
        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);
        
        LibXML_init_parser(self);
        real_dom = (xmlDocPtr) docbParseFile(filename,
                                             Sv2C(encoding, NULL));
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();

        sv_2mortal(LibXML_error);
        
        if (!real_dom) {
            if ( SvCUR( LibXML_error ) > 0 ) {
                croak(SvPV(LibXML_error, len));
            }
            XSRETURN_UNDEF;
        }
        else {
            item = hv_fetch( real_obj, "XML_LIBXML_GDOME", 16, 0 );

            if ( item != NULL && SvTRUE(*item) ) {  
                RETVAL = PmmNodeToGdomeSv( (xmlNodePtr)real_dom );
            }
            else {
                RETVAL = PmmNodeToSv((xmlNodePtr)real_dom, NULL);
            }
        }
    OUTPUT:
        RETVAL


void
parse_sax_sgml_file(self, fn, enc )
        SV * self
        SV * fn
        SV * enc
    PREINIT:
        const char * filename = Sv2C(fn, NULL);  
        const char * encoding = Sv2C(enc, NULL);
        xmlParserCtxtPtr ctxt;
        STRLEN len;
    CODE:
        LibXML_init_parser(self);
        ctxt = (xmlParserCtxtPtr) docbCreateFileParserCtxt(filename, encoding);

        if (ctxt == NULL) {
            croak("Could not create file parser context for file '%s' : %s", filename, strerror(errno));
        }

        ctxt->sax = PSaxGetHandler();
        PmmSAXInitContext( ctxt, self );
        
        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);

        docbParseDocument(ctxt);

        xmlFree(ctxt->sax);
        ctxt->sax = NULL;
        PmmSAXCloseContext(ctxt);
        xmlFreeParserCtxt(ctxt);
                
        sv_2mortal(LibXML_error);
        
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();


SV*
_parse_xml_chunk( self, svchunk, encoding="UTF-8" )
        SV * self
        SV * svchunk
        char * encoding
    PREINIT:
        xmlChar *chunk;
        xmlNodePtr rv = NULL;
        xmlNodePtr fragment= NULL;
        xmlNodePtr rv_end = NULL;
        char * ptr;
        STRLEN len;
        HV* real_obj = (HV *)SvRV(self);
        SV** item    = NULL;
        int recover;
    CODE:
        if ( encoding == NULL ) encoding = "UTF-8";
        ptr = SvPV(svchunk, len);
        if (len == 0) {
            croak("Empty string");
        }

        /* encode the chunk to UTF8 */
        chunk = Sv2C(svchunk, (const xmlChar*)encoding);

        if ( chunk != NULL ) {
            item = hv_fetch( real_obj, "XML_LIBXML_RECOVER", 18, 0 );
            recover = ( item != NULL && SvTRUE(*item) ) ? 1 : 0;
           
            LibXML_error = sv_2mortal(newSVpv("", 0));

            LibXML_init_parser(self);
            rv = domReadWellBalancedString( NULL, chunk, recover );
            LibXML_cleanup_callbacks();
            LibXML_cleanup_parser();    

            if ( rv != NULL ) {
                /* now we append the nodelist to a document
                   fragment which is unbound to a Document!!!! */
                item = hv_fetch( real_obj, "XML_LIBXML_GDOME", 16, 0 );

                /* step 1: create the fragment */
                fragment = xmlNewDocFragment( NULL );

                if ( item != NULL && SvTRUE(*item) ) {  
                    RETVAL = PmmNodeToGdomeSv( (xmlNodePtr)fragment );
                }
                else {              
                    RETVAL = PmmNodeToSv(fragment,NULL);
                }
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
                xs_warn( "bad chunk" );
                croak(SvPV(LibXML_error, len));
                XSRETURN_UNDEF;
            }
            /* free the chunk we created */
            xmlFree( chunk );
        }
    OUTPUT:
        RETVAL

void
_parse_sax_xml_chunk( self, svchunk, encoding="UTF-8" )
        SV * self
        SV * svchunk
        char * encoding
    PREINIT:
        xmlChar *chunk;
        xmlParserCtxtPtr ctxt;
        char * ptr;
        STRLEN len;
        int retCode              = -1;
        xmlNodePtr nodes         = NULL;
        xmlSAXHandlerPtr handler = NULL;
    INIT:
        if ( encoding == NULL ) encoding = "UTF-8";
        ptr = SvPV(svchunk, len);
        if (len == 0) {
            croak("Empty string");
        }
    CODE:
        /* encode the chunk to UTF8 */
        chunk = Sv2C(svchunk, (const xmlChar*)encoding);

        if ( chunk != NULL ) {
            ctxt = xmlCreateMemoryParserCtxt(ptr, len);
            if (ctxt == NULL) {
                croak("Couldn't create memory parser context: %s", strerror(errno));
            }   
            PmmSAXInitContext( ctxt, self );         
            ctxt->sax = PSaxGetHandler();

            LibXML_error = sv_2mortal(newSVpv("", 0));

            LibXML_init_parser(self);
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

            LibXML_cleanup_callbacks();
            LibXML_cleanup_parser();    
            xmlFree( chunk );

            if ( retCode == -1 ) {
                croak(SvPV(LibXML_error, len)); 
            }
        }

int
_processXIncludes( self, dom )
        SV * self
        SV * dom
    PREINIT:
        xmlDocPtr real_dom = (xmlDocPtr)PmmSvNode(dom);
        char * LibXML_ERROR_MSG;
        STRLEN len;
    CODE:
        if ( real_dom == NULL ) {
            croak("No document to process!");
        }
        LibXML_error = sv_2mortal(newSVpv("", 0));

        LibXML_init_parser(self);
        RETVAL = xmlXIncludeProcess(real_dom);        
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();

        LibXML_ERROR_MSG = SvPV(LibXML_error, len );
    
        if ( len > 0 ){
                croak(LibXML_ERROR_MSG);
                XSRETURN_UNDEF;            
        }
        else {
            RETVAL = 1;
        }
    OUTPUT:
        RETVAL

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
                tstr =  (xmlChar*)PmmDecodeString( (const char*)encoding,
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

SV*
_start_push( self, with_sax=0 ) 
        SV * self
        int with_sax
    PREINIT:
        xmlParserCtxtPtr ctxt = NULL;
    CODE:
        /* create empty context */
        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);

        if ( with_sax == 1 ) {
            ctxt = xmlCreatePushParserCtxt( PSaxGetHandler(),
                                            NULL,
                                            NULL,
                                            0,
                                            NULL );
            PmmSAXInitContext( ctxt, self );
        }
        else {
            ctxt = xmlCreatePushParserCtxt( NULL, NULL, NULL, 0, NULL );
        }
        sv_2mortal(LibXML_error);

        RETVAL = PmmContextSv( ctxt );
    OUTPUT:
        RETVAL

int
_push( self, pctxt, data ) 
        SV * self
        SV * pctxt
        SV * data
    PREINIT:
        xmlParserCtxtPtr ctxt = NULL;
        STRLEN len = 0;
        xmlChar * chunk = NULL;
    INIT:
        ctxt = PmmSvContext( pctxt );
        if ( ctxt == NULL ) {
            croak( "parser context already freed" );
            XSRETURN_UNDEF;
        }
        if ( data == &PL_sv_undef ) {
            XSRETURN_UNDEF;
        }
    CODE:
        chunk = SvPV( data, len );
        if ( len <= 0 ) {
            xs_warn( "empty string" );
            XSRETURN_UNDEF;
        }

        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);

        LibXML_init_parser(self);
        xmlParseChunk(ctxt, chunk, len, 0);

        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();    

        sv_2mortal(LibXML_error);

        RETVAL = 1;
    OUTPUT:
        RETVAL

SV*
_end_push( self, pctxt, restore ) 
        SV * self
        SV * pctxt
        int restore
    PREINIT:
        xmlParserCtxtPtr ctxt = NULL;
        xmlDocPtr doc = NULL;
        HV* real_obj = (HV *)SvRV(self);
        SV ** item = hv_fetch( real_obj, "XML_LIBXML_GDOME", 16, 0 );
    INIT:
        ctxt = PmmSvContext( pctxt );
        if ( ctxt == NULL ) {
            croak( "parser context already freed" );
            XSRETURN_UNDEF;
        }
    CODE:
        PmmNODE( SvPROXYNODE( pctxt ) ) = NULL;

        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);

        LibXML_init_parser(self);
        xmlParseChunk(ctxt, "", 0, 1); /* finish the parse */
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();    

        sv_2mortal(LibXML_error);

        if ( ctxt->node != NULL && restore == 0 ) {
            xmlFreeParserCtxt(ctxt);
            croak( "document is not wellformed" );
        }

        doc = ctxt->myDoc;
        xmlFreeParserCtxt(ctxt);
        if ( doc == NULL ){
            croak( "no document found!" );
            XSRETURN_UNDEF;
        }

        if ( item != NULL && SvTRUE(*item) ) {  
            RETVAL = PmmNodeToGdomeSv( (xmlNodePtr)doc );
        }
        else {
            RETVAL = PmmNodeToSv((xmlNodePtr)doc, NULL);
        }
    OUTPUT:
        RETVAL

void
_end_sax_push( self, pctxt ) 
        SV * self
        SV * pctxt
    PREINIT:
        xmlParserCtxtPtr ctxt = NULL;
        xmlDocPtr doc = NULL;
    INIT:
        ctxt = PmmSvContext( pctxt );
        if ( ctxt == NULL ) {
            croak( "parser context already freed" );
            XSRETURN_UNDEF;
        }
    CODE:
        PmmNODE( SvPROXYNODE( pctxt ) ) = NULL;

        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);

        LibXML_init_parser(self);
        xmlParseChunk(ctxt, "", 0, 1); /* finish the parse */
        LibXML_cleanup_callbacks();
        LibXML_cleanup_parser();    

        sv_2mortal(LibXML_error);

        PmmSAXCloseContext(ctxt);

        xmlFree(ctxt->sax);
        ctxt->sax = NULL;
        xmlFreeParserCtxt(ctxt);
        XSRETURN_UNDEF;

SV*
import_GDOME( dummy, sv_gdome, deep=1 )
        SV * dummy
        SV * sv_gdome
        int deep
    PREINIT:
        xmlNodePtr node  = NULL, retnode = NULL;
    INIT:
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
            RETVAL = sv_newmortal();
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
export_GDOME( dummy, sv_libxml, deep=1 )
        SV * dummy 
        SV * sv_libxml
        int deep
    PREINIT:
        xmlNodePtr node  = NULL, retnode = NULL;
    INIT:
#ifndef XML_LIBXML_GDOME_SUPPORT
        croak( "GDOME Support not compiled" );
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
load_default_catalog( self, filename )
        SV * self
        SV * filename
    PREINIT:
        const char * fn = Sv2C(filename, NULL);
    INIT:
        if ( fn == NULL || xmlStrlen( fn ) == 0 ) {
            croak( "cannot load catalog" );
        }
    CODE:
        warn("load defualt catalog %s", fn );
        xmlCatalogSetDebug(10);
        warn("set properties");
        /* xmlInitializeCatalog(); */
        warn("effective load");
        RETVAL = xmlLoadCatalog( fn );
		/* xmlCatalogAdd(BAD_CAST "catalog", BAD_CAST fn, NULL); */
        xmlCatalogDump(stderr);
        warn("done %d", RETVAL);
        /* xmlCatalogSetDefaults(XML_CATA_ALLOW_ALL); */
        warn("done");
    OUTPUT:
        RETVAL



int
_default_catalog( self, catalog )
        SV * self
        SV * catalog
    PREINIT:
        xmlCatalogPtr catal = (xmlCatalogPtr)SvIV(SvRV(catalog));
    INIT:
        if ( catal == NULL ) {
            croak( "empty catalog" );
        }
    CODE:
        warn( "this feature is not implemented" );
        RETVAL = 0;
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::ParserContext

void
DESTROY( self ) 
        SV * self
    CODE:
        PmmContextREFCNT_dec( SvPROXYNODE( self ) );


MODULE = XML::LibXML         PACKAGE = XML::LibXML::Document

SV *
_toString(self, format=0)
        SV * self
        int format
    PREINIT:
        xmlDocPtr real_dom;
        xmlChar *result=NULL;
        int len=0;
        SV* internalFlag = NULL;
        int oldTagFlag = xmlSaveNoEmptyTags;
        xmlDtdPtr intSubset = NULL;
    CODE:
        real_dom = (xmlDocPtr)PmmNODE(SvPROXYNODE(self));
        internalFlag = perl_get_sv("XML::LibXML::setTagCompression", 0);
        if( internalFlag ) {
            xmlSaveNoEmptyTags = SvTRUE(internalFlag);
        }

        internalFlag = perl_get_sv("XML::LibXML::skipDTD", 0);
        if ( internalFlag && SvTRUE(internalFlag) ) {
            intSubset = xmlGetIntSubset( real_dom );
            if ( intSubset )
                xmlUnlinkNode( (xmlNodePtr)intSubset );
        }

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

        if ( intSubset != NULL ) {
            if (real_dom->children == NULL)
                 xmlAddChild((xmlNodePtr) real_dom, (xmlNodePtr) intSubset);
            else
                xmlAddPrevSibling(real_dom->children, (xmlNodePtr) intSubset);
        }

        xmlSaveNoEmptyTags = oldTagFlag;

    	if (result == NULL) {
	        # warn("Failed to convert doc to string");           
            XSRETURN_UNDEF;
    	} else {
            # warn("%s, %d\n",result, len);
            RETVAL = C2Sv( result, real_dom->encoding );
            xmlFree(result);
        }
    OUTPUT:
        RETVAL

int 
toFH( self, filehandler, format=0 )
        SV * self
        SV * filehandler
        int format
    PREINIT:
        xmlOutputBufferPtr buffer;
        const xmlChar * encoding = NULL;
        xmlCharEncodingHandlerPtr handler = NULL;
        SV* internalFlag = NULL;
        int oldTagFlag = xmlSaveNoEmptyTags;
        xmlDtdPtr intSubset = NULL;
        xmlDocPtr doc = (xmlDocPtr)PmmSvNode( self );
        int t_indent_var = xmlIndentTreeOutput;
    CODE:
        internalFlag = perl_get_sv("XML::LibXML::setTagCompression", 0);
        if( internalFlag ) {
            xmlSaveNoEmptyTags = SvTRUE(internalFlag);
        }

        internalFlag = perl_get_sv("XML::LibXML::skipDTD", 0);
        if ( internalFlag && SvTRUE(internalFlag) ) {
            intSubset = xmlGetIntSubset( doc );
            if ( intSubset )
                xmlUnlinkNode( (xmlNodePtr)intSubset );
        }

        xmlRegisterDefaultOutputCallbacks();
        encoding = ((xmlDocPtr) PmmSvNode(self))->encoding;
        if ( encoding != NULL ) {
            if ( xmlParseCharEncoding(encoding) != XML_CHAR_ENCODING_UTF8) {
                handler = xmlFindCharEncodingHandler(encoding);
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

        RETVAL = xmlSaveFormatFileTo( buffer, 
                                      doc,
                                      encoding,
                                      format);

        if ( intSubset != NULL ) {
            if (doc->children == NULL)
                xmlAddChild((xmlNodePtr) doc, (xmlNodePtr) intSubset);
            else
                xmlAddPrevSibling(doc->children, (xmlNodePtr) intSubset);
        }
    
        xmlIndentTreeOutput = t_indent_var;
        xmlSaveNoEmptyTags = oldTagFlag;
    OUTPUT:
        RETVAL    

int 
toFile( self, filename, format=0 )
        SV * self
        char * filename
        int format
    PREINIT:
        SV* internalFlag = NULL;
        int oldTagFlag = xmlSaveNoEmptyTags;
    CODE:
        internalFlag = perl_get_sv("XML::LibXML::setTagCompression", 0);
        if( internalFlag ) {
            xmlSaveNoEmptyTags = SvTRUE(internalFlag);
        }

        if ( format <= 0 ) {
            xs_warn( "use no formated toFile!" );
            RETVAL = xmlSaveFile( filename, (xmlDocPtr)PmmSvNode(self) );
        }
        else {
            int t_indent_var = xmlIndentTreeOutput;
            xmlIndentTreeOutput = 1;
            RETVAL =xmlSaveFormatFile( filename,
                                       (xmlDocPtr)PmmSvNode(self),
                                       format);
            xmlIndentTreeOutput = t_indent_var;
        }

        xmlSaveNoEmptyTags = oldTagFlag;   
        if ( RETVAL > 0 ) 
            RETVAL = 1;
        else 
            XSRETURN_UNDEF;
    OUTPUT:
        RETVAL

SV *
toStringHTML(self)
        SV * self
    PREINIT:
        xmlDocPtr real_dom;
        xmlChar *result=NULL;
        int len=0;
    CODE:
        real_dom = (xmlDocPtr)PmmNODE(SvPROXYNODE(self));
        # warn( "use no formated toString!" );
        htmlDocDumpMemory(real_dom, &result, &len);

    	if (result == NULL) {
            XSRETURN_UNDEF;
      	} else {
            # warn("%s, %d\n",result, len);
            RETVAL = newSVpvn((char *)result, (STRLEN)len);
            xmlFree(result);
        }
    OUTPUT:
        RETVAL


const char *
URI( pdoc )
        SV * pdoc
    CODE:
        RETVAL = xmlStrdup(((xmlDocPtr)PmmSvNode(pdoc))->URL );
    OUTPUT:
        RETVAL

void
setBaseURI( doc, new_URI )
        SV * doc
        char * new_URI
    CODE:
        if (new_URI) {
            xmlFree((xmlChar*)((xmlDocPtr)PmmSvNode(doc))->URL );
            ((xmlDocPtr)PmmSvNode(doc))->URL = xmlStrdup((const xmlChar*)new_URI);
        }



SV*
createDocument( CLASS, version="1.0", encoding=NULL )
        char * CLASS
        char * version 
        char * encoding
    ALIAS:
        XML::LibXML::Document::new = 1
        XML::LibXML::createDocument = 2
    PREINIT:
        xmlDocPtr doc=NULL;
    CODE:
        doc = xmlNewDoc(version);
        if (encoding && *encoding!=0) {
            doc->encoding = xmlStrdup(encoding);
        }
        RETVAL = PmmNodeToSv((xmlNodePtr)doc,NULL);
    OUTPUT:
        RETVAL

SV* 
createInternalSubset( doc, Pname, extID, sysID )
        SV * doc
        SV * Pname
        SV * extID
        SV * sysID
    PREINIT:
        xmlDocPtr document = NULL;
        xmlDtdPtr dtd = NULL;
        xmlChar * name = NULL;
        xmlChar * externalID = NULL;
        xmlChar * systemID = NULL; 
    CODE:
        document = (xmlDocPtr)PmmSvNode( doc );
        if ( document == NULL ) {
            XSRETURN_UNDEF;   
        }

        name = Sv2C( Pname, NULL );
        if ( name == NULL ) {
            XSRETURN_UNDEF;
        }  

        externalID = Sv2C(extID, NULL);
        systemID   = Sv2C(sysID, NULL);

        dtd = xmlCreateIntSubset( document, name, externalID, systemID );
        xmlFree(externalID);
        xmlFree(systemID);
        xmlFree(name);
        if ( dtd ) {
            RETVAL = PmmNodeToSv( (xmlNodePtr)dtd, SvPROXYNODE(doc) );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV* 
createExternalSubset( doc, Pname, extID, sysID )
        SV * doc
        SV * Pname
        SV * extID
        SV * sysID
    PREINIT:
        xmlDocPtr document = NULL;
        xmlDtdPtr dtd = NULL;
        xmlChar * name = NULL;
        xmlChar * externalID = NULL;
        xmlChar * systemID = NULL; 
    CODE:
        document = (xmlDocPtr)PmmSvNode( doc );
        if ( document == NULL ) {
            XSRETURN_UNDEF;   
        }

        name = Sv2C( Pname, NULL );
        if ( name == NULL ) {
            XSRETURN_UNDEF;
        }  

        externalID = Sv2C(extID, NULL);
        systemID   = Sv2C(sysID, NULL);

        dtd = xmlNewDtd( document, name, externalID, systemID );

        xmlFree(externalID);
        xmlFree(systemID);
        xmlFree(name);
        if ( dtd ) {
            RETVAL = PmmNodeToSv( (xmlNodePtr)dtd, SvPROXYNODE(doc) );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV* 
createDTD( doc, Pname, extID, sysID )
        SV * doc
        SV * Pname
        SV * extID
        SV * sysID
    PREINIT:
        xmlDocPtr document = NULL;
        xmlDtdPtr dtd = NULL;
        xmlChar * name = NULL;
        xmlChar * externalID = NULL;
        xmlChar * systemID = NULL; 
    CODE:
        document = (xmlDocPtr)PmmSvNode( doc );
        if ( document == NULL ) {
            XSRETURN_UNDEF;   
        }

        name = Sv2C( Pname, NULL );
        if ( name == NULL ) {
            XSRETURN_UNDEF;
        }  

        externalID = Sv2C(extID, NULL);
        systemID   = Sv2C(sysID, NULL);

        dtd = xmlNewDtd( NULL, name, externalID, systemID );
        dtd->doc = document;

        xmlFree(externalID);
        xmlFree(systemID);
        xmlFree(name);
        if ( dtd ) {
            RETVAL = PmmNodeToSv( (xmlNodePtr)dtd, SvPROXYNODE(doc) );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
createDocumentFragment( doc )
        SV * doc
    PREINIT:
        xmlDocPtr real_doc;
        xmlNodePtr fragment= NULL;
    CODE:
        real_doc = (xmlDocPtr)PmmSvNode(doc);
        RETVAL = PmmNodeToSv(xmlNewDocFragment(real_doc),SvPROXYNODE(doc));
    OUTPUT:
        RETVAL

SV*
createElement( dom, name )
        SV * dom
        SV* name
    PREINIT:
        xmlNodePtr newNode;
        xmlDocPtr real_doc;
        xmlChar * elname = NULL;
        ProxyNodePtr docfrag = NULL;
    CODE:
        STRLEN len;
        real_doc = (xmlDocPtr)PmmSvNode(dom);
        docfrag = PmmNewFragment( real_doc );
       
        elname = nodeSv2C( name , (xmlNodePtr) real_doc );
        if ( elname != NULL || xmlStrlen(elname) > 0 ) {
            newNode = xmlNewNode(NULL , elname);
            xmlFree(elname);
            if ( newNode != NULL ) {        
                newNode->doc = real_doc;
                domAppendChild( PmmNODE(docfrag), newNode );
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

SV*
createElementNS( pdoc, nsURI, name )
        SV * pdoc
        SV * nsURI
        SV * name
    PREINIT:
        xmlChar * ename        = NULL;
        xmlChar * prefix       = NULL;
        xmlChar * localname    = NULL;
        xmlChar * eURI         = NULL;
        const xmlChar * pchar  = NULL;
        xmlNsPtr ns            = NULL;
        xmlDocPtr doc          = NULL;
        ProxyNodePtr docfrag   = NULL;
        xmlNodePtr newNode     = NULL;
    CODE:
        doc = (xmlDocPtr)PmmSvNode( pdoc );
        ename = nodeSv2C( name , (xmlNodePtr) doc );
        eURI  = Sv2C( nsURI , NULL );

        if ( eURI != NULL && xmlStrlen(eURI)!=0 ){
            localname = xmlSplitQName2(ename, &prefix);
            if ( localname == NULL ) {
                localname = xmlStrdup( ename );
            }

            newNode = xmlNewNode( NULL , localname );
            newNode->doc = doc;
            
            ns = xmlSearchNsByHref( doc, newNode, eURI );
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
        
            newNode = xmlNewNode( NULL , localname );
            newNode->doc = doc;
        }

        xmlSetNs(newNode, ns);

        docfrag = PmmNewFragment( doc );
        domAppendChild( PmmNODE(docfrag), newNode );
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
createTextNode( doc, content )
        SV * doc
        SV * content
    PREINIT:
        xmlNodePtr newNode;
        xmlDocPtr real_doc;
        xmlChar * elname = NULL;
        ProxyNodePtr docfrag = NULL;
    CODE:
        STRLEN len;
        real_doc = (xmlDocPtr)PmmSvNode(doc);
        docfrag = PmmNewFragment( real_doc );
       
        elname = nodeSv2C( content , (xmlNodePtr) real_doc );
        if ( elname != NULL || xmlStrlen(elname) > 0 ) {
            newNode = xmlNewDocText( real_doc, elname );
            xmlFree(elname);
            if ( newNode != NULL ) {        
                newNode->doc = real_doc;
                domAppendChild( PmmNODE(docfrag), newNode );
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
createComment( doc , content )
        SV * doc
        SV * content
    PREINIT:
        xmlNodePtr newNode;
        xmlDocPtr real_doc;
        xmlChar * elname = NULL;
        ProxyNodePtr docfrag = NULL;
    CODE:
        STRLEN len;
        real_doc = (xmlDocPtr)PmmSvNode(doc);
        docfrag = PmmNewFragment( real_doc );
       
        elname = nodeSv2C( content , (xmlNodePtr) real_doc );
        if ( elname != NULL || xmlStrlen(elname) > 0 ) {
            newNode = xmlNewDocComment( real_doc, elname );
            xmlFree(elname);
            if ( newNode != NULL ) {        
                newNode->doc = real_doc;
                domAppendChild( PmmNODE(docfrag), newNode );
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
createCDATASection( doc, content )
        SV * doc
        SV * content
    PREINIT:
        xmlNodePtr newNode;
        xmlDocPtr real_doc;
        xmlChar * elname = NULL;
        ProxyNodePtr docfrag = NULL;
    CODE:
        real_doc = (xmlDocPtr)PmmSvNode(doc);
        docfrag = PmmNewFragment( real_doc );
       
        elname = nodeSv2C( content , (xmlNodePtr) real_doc );
        if ( elname != NULL || xmlStrlen(elname) > 0 ) {
            newNode = xmlNewCDataBlock( real_doc, elname, xmlStrlen(elname) );
            xmlFree(elname);
            if ( newNode != NULL ) {        
                newNode->doc = real_doc;
                domAppendChild( PmmNODE(docfrag), newNode );
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

SV*
createEntityReference( pdoc , pname )
        SV * pdoc 
        SV * pname
    PREINIT:
        xmlNodePtr newNode;
        xmlDocPtr doc = (xmlDocPtr)PmmSvNode(pdoc);
        xmlChar * name = Sv2C( pname, NULL );
        ProxyNodePtr docfrag = NULL;        
    CODE:
        if ( name == NULL ) {
            XSRETURN_UNDEF;
        }
        newNode = xmlNewReference( doc, name );
        xmlFree(name);
        if ( newNode == NULL ) {
            XSRETURN_UNDEF;
        }
        docfrag = PmmNewFragment( doc );
        domAppendChild( PmmNODE(docfrag), newNode );
        RETVAL = PmmNodeToSv( newNode, docfrag );
    OUTPUT:
        RETVAL

SV*
createAttribute( pdoc, pname, pvalue=&PL_sv_undef )
        SV * pdoc
        SV * pname
        SV * pvalue
    PREINIT:
        xmlDocPtr doc = (xmlDocPtr)PmmSvNode( pdoc );
        xmlChar * name = NULL;
        xmlChar * value = NULL;
        xmlAttrPtr self = NULL;
    CODE:
        name = nodeSv2C( pname , (xmlNodePtr) doc );
        if ( name == NULL ) {
            XSRETURN_UNDEF;
        }
        value = nodeSv2C( pvalue , (xmlNodePtr) doc );
        self = xmlNewDocProp( doc, name, value );
        RETVAL = PmmNodeToSv((xmlNodePtr)self,NULL); 
        xmlFree(name);
        if ( value ) {
            xmlFree(value);
        }
    OUTPUT:
        RETVAL

SV*
createAttributeNS( pdoc, URI, pname, pvalue=&PL_sv_undef )
        SV * pdoc
        SV * URI
        SV * pname
        SV * pvalue
    PREINIT:
        xmlDocPtr doc = (xmlDocPtr)PmmSvNode( pdoc );
        xmlChar * name = NULL;
        xmlChar * value = NULL;
        xmlChar * prefix = NULL;
        const xmlChar * pchar = NULL;
        xmlChar * localname = NULL;
        xmlChar * nsURI = NULL;
        xmlAttrPtr self = NULL;
        xmlNsPtr ns = NULL;
    CODE:
        name  = nodeSv2C( pname , (xmlNodePtr) doc );
        if( name == NULL ) {
            XSRETURN_UNDEF;
        }

        nsURI = Sv2C( URI , NULL );
        value = nodeSv2C( pvalue, (xmlNodePtr) doc  );

        if ( nsURI != NULL && xmlStrlen(nsURI) > 0 ) {
            xmlNodePtr root = xmlDocGetRootElement( doc );
            if ( root ) {
                pchar = xmlStrchr(name, ':');
                if ( pchar != NULL ) {
                    localname = xmlSplitQName2(name, &prefix);
                }
                else {
                    localname = xmlStrdup( name );
                }
                ns = xmlSearchNsByHref( doc, root, nsURI );
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

                self = xmlNewDocProp( doc, localname, value );
                self->ns = ns;

                RETVAL = PmmNodeToSv((xmlNodePtr)self, NULL );
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
            self = xmlNewDocProp( doc, name, value );
            RETVAL = PmmNodeToSv((xmlNodePtr)self,NULL);
            xmlFree(name);
            if ( value ) {
                xmlFree(value);
            }
        }
    OUTPUT:
        RETVAL

SV*
createProcessingInstruction(self, name, value=&PL_sv_undef)
        SV * self
        SV * name
        SV * value
    ALIAS:
        createPI = 1
    PREINIT:
        xmlDocPtr doc = (xmlDocPtr)PmmSvNode(self);
        xmlChar * n = NULL;
        xmlChar * v = NULL;
        xmlNodePtr PI = NULL;
    CODE:
        n = nodeSv2C(name, (xmlNodePtr)doc);
        if ( !n ) {
            XSRETURN_UNDEF;
        }
        v = nodeSv2C(value, (xmlNodePtr)doc);
        PI = xmlNewPI(n,v);      
        PI->doc = doc;
        RETVAL = PmmNodeToSv(PI, SvPROXYNODE(self));
        xmlFree(v);
        xmlFree(n);
    OUTPUT:
        RETVAL



void 
_setDocumentElement( dom , proxy )
        SV * dom
        SV * proxy
    PREINIT:
        xmlDocPtr real_dom;
        xmlNodePtr elem, oelem;
        SV* oldsv =NULL;
    INIT:
        elem = PmmSvNode(proxy);
        if ( elem == NULL ) {
            XSRETURN_UNDEF;
        }          
    CODE:
        real_dom = (xmlDocPtr)PmmSvNode(dom);
        /* please correct me if i am wrong: the document element HAS to be
         * an ELEMENT NODE
         */ 
        if ( elem->type == XML_ELEMENT_NODE ) {
            if ( real_dom != elem->doc ) {
                domImportNode( real_dom, elem, 1 );
            }

            oelem = xmlDocGetRootElement( real_dom );
            if ( oelem == NULL || oelem->_private == NULL ) {
                xmlDocSetRootElement( real_dom, elem );
            }
            else {
                xmlReplaceNode( oelem, elem );
            }

            if ( elem->_private != NULL ) {
                PmmFixOwner( SvPROXYNODE(proxy), SvPROXYNODE(dom));
            }
        }

SV *
documentElement( dom )
        SV * dom
    ALIAS:
        XML::LibXML::Document::getDocumentElement = 1
    PREINIT:
        xmlNodePtr elem;
        xmlDocPtr real_dom;
    CODE:
        real_dom = (xmlDocPtr)PmmSvNode(dom);
        elem = xmlDocGetRootElement( real_dom );
        if ( elem ) {
            RETVAL = PmmNodeToSv(elem, SvPROXYNODE(dom));
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV *
externalSubset( doc )
        SV * doc
    PREINIT:
        xmlDtdPtr dtd;
    CODE:
        if ( ((xmlDocPtr)PmmSvNode(doc))->extSubset == NULL ) {
            XSRETURN_UNDEF;
        }

        dtd = ((xmlDocPtr)PmmSvNode(doc))->extSubset;
        RETVAL = PmmNodeToSv((xmlNodePtr)dtd, SvPROXYNODE(doc));
    OUTPUT:
        RETVAL
        
SV *
internalSubset( doc )
        SV * doc
    PREINIT:
        xmlDtdPtr dtd;
    CODE:
        if ( ((xmlDocPtr)PmmSvNode(doc))->intSubset == NULL ) {
            XSRETURN_UNDEF;
        }

        dtd = ((xmlDocPtr)PmmSvNode(doc))->intSubset;
        RETVAL = PmmNodeToSv((xmlNodePtr)dtd, SvPROXYNODE(doc));
    OUTPUT:
        RETVAL

void
setExternalSubset( document, extdtd )
        SV * document
        SV * extdtd
    PREINIT:
        xmlDocPtr doc = NULL;
        xmlDtdPtr dtd = NULL;
        xmlDtdPtr olddtd = NULL;
    CODE:
        doc = (xmlDocPtr)PmmSvNode(document);
        dtd = (xmlDtdPtr)PmmSvNode(extdtd);
        if ( dtd && dtd != doc->extSubset ) {
            if ( dtd->doc != doc ) {
                croak( "can't import DTDs" );
                domImportNode( doc, (xmlNodePtr) dtd,1);
            }
    
            if ( dtd == doc->intSubset ) {
                xmlUnlinkNode( (xmlNodePtr)dtd );
                doc->intSubset = NULL;
            }

            olddtd = doc->extSubset;
            if ( olddtd && olddtd->_private == NULL ) {
                xmlFreeDtd( olddtd );
            }
            doc->extSubset = dtd;
        }

void
setInternalSubset( document, extdtd )
        SV * document
        SV * extdtd
    PREINIT:
        xmlDocPtr doc = NULL;
        xmlDtdPtr dtd = NULL;
        xmlDtdPtr olddtd = NULL;
    CODE:
        doc = (xmlDocPtr)PmmSvNode(document);
        dtd = (xmlDtdPtr)PmmSvNode(extdtd);
        if ( dtd && dtd != doc->intSubset ) {
            if ( dtd->doc != doc ) {
                croak( "can't import DTDs" );
                domImportNode( doc, (xmlNodePtr) dtd,1);
            }
    
            if ( dtd == doc->extSubset ) {
                doc->extSubset = NULL;
            }

            olddtd = xmlGetIntSubset( doc );
            if( olddtd ) {
                xmlReplaceNode( (xmlNodePtr)olddtd, (xmlNodePtr) dtd );
                if ( olddtd->_private == NULL ) {
                    xmlFreeDtd( olddtd );
                }
            }
            else {
                if (doc->children == NULL)
                    xmlAddChild((xmlNodePtr) doc, (xmlNodePtr) dtd);
                else
                    xmlAddPrevSibling(doc->children, (xmlNodePtr) dtd);
            }
            doc->intSubset = dtd;
        }

SV *
removeInternalSubset( document ) 
        SV * document
    PREINIT:
        xmlDocPtr doc = (xmlDocPtr)PmmSvNode(document);
        xmlDtdPtr dtd = NULL;
    CODE:
        dtd = xmlGetIntSubset(doc);
        if ( !dtd ) {
            XSRETURN_UNDEF;   
        }
        xmlUnlinkNode( (xmlNodePtr)dtd );
        doc->intSubset = NULL;
        RETVAL = PmmNodeToSv( (xmlNodePtr)dtd, SvPROXYNODE(document) );
    OUTPUT:
        RETVAL

SV *
removeExternalSubset( document ) 
        SV * document
    PREINIT:
        xmlDocPtr doc = (xmlDocPtr)PmmSvNode(document);
        xmlDtdPtr dtd = NULL;
    CODE:
        dtd = doc->extSubset;
        if ( !dtd ) {
            XSRETURN_UNDEF;   
        }
        doc->extSubset = NULL;
        RETVAL = PmmNodeToSv( (xmlNodePtr)dtd, SvPROXYNODE(document) );
    OUTPUT:
        RETVAL

SV *
importNode( dom, node, dummy=0 ) 
        SV * dom
        SV * node
        int dummy
    PREINIT:
        xmlNodePtr ret = NULL;
        xmlNodePtr real_node = NULL;
        xmlDocPtr real_dom;
    CODE:
        real_dom = (xmlDocPtr)PmmSvNode(dom);
        real_node=  PmmSvNode(node);
   
        if ( real_node->type == XML_DOCUMENT_NODE 
             || real_node->type == XML_HTML_DOCUMENT_NODE ) {
            croak( "Can't import Documents!" );
            XSRETURN_UNDEF;
        }

        ret = domImportNode( real_dom, real_node, 0 );
        if ( ret ) {
            RETVAL = PmmNodeToSv( ret, SvPROXYNODE(dom));
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV *
adoptNode( dom, node ) 
        SV * dom
        SV * node
    PREINIT:
        xmlNodePtr ret = NULL;
        ProxyNodePtr frag = NULL;
        xmlNodePtr real_node = NULL;
        xmlDocPtr real_dom;
    CODE:
        real_dom = (xmlDocPtr)PmmSvNode(dom);
        real_node=  PmmSvNode(node);

        if ( real_node->type == XML_DOCUMENT_NODE 
             || real_node->type == XML_HTML_DOCUMENT_NODE ) {
            croak( "Can't adopt Documents!" );
            XSRETURN_UNDEF;
        }

        ret = domImportNode( real_dom, real_node, 1 );
        if ( ret ) {
            frag = PmmNewFragment( real_dom );
            domAppendChild( PmmNODE(frag), ret );
            RETVAL = PmmNodeToSv(real_node, NULL);
            PmmFixOwner(SvPROXYNODE(RETVAL),frag);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

char*
encoding( self )
        SV* self
    ALIAS:
        XML::LibXML::Document::getEncoding    = 1
        XML::LibXML::Document::actualEncoding = 2
    CODE:
        if( self != NULL && self!=&PL_sv_undef) {
            RETVAL = xmlStrdup((xmlChar*)((xmlDocPtr)PmmSvNode(self))->encoding );
        }
    OUTPUT:
        RETVAL

void
setEncoding( self, encoding )
        SV* self
        char *encoding
    CODE:
        ((xmlDocPtr)PmmSvNode(self))->encoding = xmlStrdup( encoding );

int
standalone( self ) 
        SV * self
    CODE:
        RETVAL = ((xmlDocPtr)PmmSvNode(self))->standalone;
    OUTPUT:
        RETVAL

void
setStandalone( self, value = 0 )
        SV * self
        int value
    CODE:
        if ( value > 0 ) {
            ((xmlDocPtr)PmmSvNode(self))->standalone = 1;
        }
        else if ( value < 0 ) {
            ((xmlDocPtr)PmmSvNode(self))->standalone = -1;
        }
        else {
            ((xmlDocPtr)PmmSvNode(self))->standalone = 0;
        }

char*
version( self ) 
         SV * self
    ALIAS:
        XML::LibXML::Document::getVersion = 1
    CODE:
        if( self != NULL && self != &PL_sv_undef ) {
            RETVAL = xmlStrdup( ((xmlDocPtr)PmmSvNode(self))->version );
        }
    OUTPUT:
        RETVAL

void
setVersion( self, version )
        SV* self
        char *version
    CODE:
        ((xmlDocPtr)PmmSvNode(self))->version = xmlStrdup( version );

int
compression( self )
        SV * self
    CODE:
        RETVAL = xmlGetDocCompressMode((xmlDocPtr)PmmSvNode(self));
    OUTPUT:
        RETVAL

void
setCompression( self, zLevel )
        SV * self
        int zLevel
    CODE:
        xmlSetDocCompressMode((xmlDocPtr)PmmSvNode(self), zLevel);


int
is_valid(self, ...)
        SV * self
    PREINIT:
        xmlDocPtr doc = (xmlDocPtr)PmmSvNode(self);
        xmlValidCtxt cvp;
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
                dtd = (xmlDtdPtr)PmmSvNode(dtd_sv);
            }
            RETVAL = xmlValidateDtd(&cvp, doc, dtd);
        }
        else {
            RETVAL = xmlValidateDocument(&cvp, doc);
        }
    OUTPUT:
        RETVAL

int
validate(self, ...)
        SV * self
    PREINIT:
        xmlDocPtr doc = (xmlDocPtr)PmmSvNode(self);
        xmlValidCtxt cvp;
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
                dtd = (xmlDtdPtr)PmmSvNode(dtd_sv);
            }
            else {
                croak("is_valid: argument must be a DTD object");
            }
            RETVAL = xmlValidateDtd(&cvp, doc , dtd);

        }
        else {
            RETVAL = xmlValidateDocument(&cvp, doc);
        }
        if (RETVAL == 0) {
            croak(SvPV(LibXML_error, n_a));
        }
    OUTPUT:
        RETVAL


MODULE = XML::LibXML         PACKAGE = XML::LibXML::Node

void
DESTROY( node )
        SV * node
    CODE:
        xs_warn("DESTROY NODE\n");
        PmmREFCNT_dec(SvPROXYNODE(node));

SV*
nodeName( node )
        SV* node
    ALIAS:
        XML::LibXML::Node::getName = 1
        XML::LibXML::Element::tagName = 2
    PREINIT:
        char * name;
        xmlNodePtr xnode = PmmSvNode(node);
    INIT:
        if( xnode == NULL ) {
            croak( "lost my node" );
        }
        if( xnode->name == NULL ) {
            croak( "lost the name!" );
        }
    CODE:
        name =  domName( xnode );
        RETVAL = C2Sv(name,NULL);
        xmlFree( name );
    OUTPUT:
        RETVAL

SV*
localname( node )
        SV * node
    ALIAS:
        XML::LibXML::Node::getLocalName = 1
        XML::LibXML::Attr::name         = 2
    PREINIT:
        xmlNodePtr rnode = PmmSvNode(node);
        xmlChar * lname;
    CODE:
        RETVAL = C2Sv(rnode->name,NULL);
    OUTPUT:
        RETVAL

SV*
prefix( node )
        SV * node
    ALIAS:
        XML::LibXML::Node::getPrefix = 1
    PREINIT:
        xmlNodePtr rnode = PmmSvNode(node);
        xmlChar * prefix;
    CODE:
        if( rnode->ns != NULL
            && rnode->ns->prefix != NULL ) {            
            RETVAL = C2Sv(rnode->ns->prefix, NULL);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
namespaceURI( self )
        SV * self
    ALIAS:
        getNamespaceURI = 1
    PREINIT:
        xmlNodePtr rnode = PmmSvNode(self);
        xmlChar * nsURI;
    CODE:
        if ( rnode->ns != NULL
             && rnode->ns->href != NULL ) {
            nsURI =  xmlStrdup(rnode->ns->href);
            RETVAL = C2Sv( nsURI, NULL );
            xmlFree( nsURI );
        }
        else {
            XSRETURN_UNDEF;
        }        
    OUTPUT:
        RETVAL
        

SV*
lookupNamespaceURI( node, svprefix=&PL_sv_undef )
        SV * node
        SV * svprefix
    PREINIT:
        xmlNodePtr rnode = PmmSvNode(node);
        xmlChar * nsURI;
        xmlChar * prefix = NULL;
    CODE:
        prefix = nodeSv2C( svprefix , PmmSvNode(node) );
        if ( prefix != NULL && xmlStrlen(prefix) > 0) {
            xmlNsPtr ns = xmlSearchNs( rnode->doc, rnode, prefix );
            xmlFree( prefix );
            if ( ns != NULL ) {
                nsURI = xmlStrdup(ns->href);
                RETVAL = C2Sv( nsURI, NULL );
                xmlFree( nsURI );
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

SV*
lookupNamespacePrefix( node, svuri )
        SV * node
        SV * svuri
    PREINIT:
        xmlNodePtr rnode = PmmSvNode(node);
        xmlChar * nsprefix;
        xmlChar * href = NULL;
    CODE:
        href = nodeSv2C( svuri , PmmSvNode(node) );
        if ( href != NULL && xmlStrlen(href) > 0) {
            xmlNsPtr ns = xmlSearchNsByHref( rnode->doc, rnode, href );
            xmlFree( href );
            if ( ns != NULL ) {
                nsprefix = xmlStrdup( ns->prefix );
                RETVAL = C2Sv( nsprefix, NULL );
                xmlFree(nsprefix);
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
setNodeName( pnode , value )
        SV * pnode
        SV* value
    ALIAS:
        setName = 1
    PREINIT:
        xmlNodePtr node = PmmSvNode(pnode);
        xmlChar* string;
        xmlChar* localname;
        xmlChar* prefix;
    INIT:
        if( node == NULL ) {
            croak( "lost my node" );
        }
    CODE:
        string = nodeSv2C( value , node );
        if( node->ns ){
            localname = xmlSplitQName2(string, &prefix);
            xmlNodeSetName(node, localname );
            xmlFree(localname);
            xmlFree(prefix);
        }
        else {
            xs_warn("node name normal\n");
            xmlNodeSetName(node, string );
        }
        xmlFree(string);

SV*
nodeValue( proxy_node, useDomEncoding = &PL_sv_undef ) 
        SV * proxy_node 
        SV * useDomEncoding
    ALIAS:
        XML::LibXML::Attr::value     = 1
        XML::LibXML::Attr::getValue  = 2
        XML::LibXML::Text::data      = 3
        XML::LibXML::Node::getValue  = 4
        XML::LibXML::Node::getData   = 5
    PREINIT:
        xmlNodePtr node;
        xmlChar * content = NULL;
    CODE:
        content = domGetNodeValue( PmmSvNode(proxy_node) ); 
        
        if ( content != NULL ) {
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

int 
nodeType( node ) 
        SV* node
    ALIAS:
        XML::LibXML::Node::getType = 1
    PREINIT:
        xmlNodePtr xnode = PmmSvNode(node);
    INIT:
        if ( xnode == NULL ) {
            croak( "lost my node" );
        }
    CODE:
        RETVAL =  xnode->type;
    OUTPUT:
        RETVAL

SV*
parentNode( self )
        SV *self
    ALIAS:
        XML::LibXML::Attr::ownerElement    = 1
        XML::LibXML::Node::getParentNode   = 2
        XML::LibXML::Attr::getOwnerElement = 3
    CODE:
        RETVAL = PmmNodeToSv( PmmSvNode(self)->parent,
                              PmmOWNERPO( SvPROXYNODE(self) ) ); 
    OUTPUT:
        RETVAL

SV*
nextSibling( self ) 
        SV *self
    ALIAS:
        getNextSibling = 1
    CODE:
        RETVAL = PmmNodeToSv( PmmSvNode(self)->next,
                              PmmOWNERPO( SvPROXYNODE(self) ) ); 
    OUTPUT:
        RETVAL

SV*
previousSibling( self )
        SV *self
    ALIAS:
        getPreviousSibling = 1
    CODE:
        RETVAL = PmmNodeToSv( PmmSvNode(self)->prev,
                              PmmOWNERPO( SvPROXYNODE(self) ) ); 
    OUTPUT:
        RETVAL

void
_childNodes( node )
        SV* node
    ALIAS:
        XML::LibXML::Node::getChildnodes = 1
    PREINIT:
        xmlNodePtr cld;
        SV * element;
        int len = 0;
        int wantarray = GIMME_V;
    PPCODE:
        if ( PmmSvNode(node)->type != XML_ATTRIBUTE_NODE ) {
            cld = PmmSvNode(node)->children;
            xs_warn("childnodes start");
            while ( cld ) {
                if( wantarray != G_SCALAR ) {
	                element = PmmNodeToSv(cld, PmmOWNERPO(SvPROXYNODE(node)) );
                    XPUSHs(sv_2mortal(element));
                }
                cld = cld->next;
                len++;
            }
        }
        if ( wantarray == G_SCALAR ) {
            XPUSHs(sv_2mortal(newSViv(len)) );
        }

SV*
firstChild( self )
        SV *self
    ALIAS:
        getFirstChild = 1
    CODE:
        RETVAL = PmmNodeToSv( PmmSvNode(self)->children,
                              PmmOWNERPO( SvPROXYNODE(self) ) ); 
    OUTPUT:
        RETVAL

SV*
lastChild( self )
        SV *self
    ALIAS:
        getLastChild = 1
    CODE:
        RETVAL = PmmNodeToSv( PmmSvNode(self)->last,
                              PmmOWNERPO( SvPROXYNODE(self) ) ); 
    OUTPUT:
        RETVAL

void
_attributes( node )
        SV* node
    ALIAS:
        XML::LibXML::Node::getAttributes = 1
    PREINIT:
        xmlAttrPtr attr = NULL;
        xmlNodePtr real_node = NULL;
        xmlNsPtr ns = NULL;
        SV * element;
        int len=0;
        int wantarray = GIMME_V;
    PPCODE:
        real_node = PmmSvNode(node);
        if ( real_node->type != XML_ATTRIBUTE_NODE ) {
            attr      = real_node->properties;
            while ( attr != NULL ) {
                if ( wantarray != G_SCALAR ) {
                    element = PmmNodeToSv((xmlNodePtr)attr,
                                           PmmOWNERPO(SvPROXYNODE(node)) );
                    XPUSHs(sv_2mortal(element));
                }
                attr = attr->next;
                len++;
            }

            ns = real_node->nsDef;
            while ( ns != NULL ) {
                const char * CLASS = "XML::LibXML::Namespace";
                if ( wantarray != G_SCALAR ) {
                    /* namespace handling is kinda odd:
                     * as soon we have a namespace isolated from its
                     * owner, we loose the context. therefore it is 
                     * forbidden to access the NS information directly.
                     * instead the use will recieve a copy of the real
                     * namespace, that can be destroied and is not 
                     * bound to a document.
                     *
                     * this avoids segfaults in the end.
                     */
                    xmlNsPtr tns = xmlCopyNamespace(ns);
                    element = sv_newmortal();
                    XPUSHs(sv_setref_pv( element, 
                                         (char *)CLASS, 
                                         (void*)tns));
                }
                ns = ns->next;
                len++;
            }
        }
        if( wantarray == G_SCALAR ) {
            XPUSHs( sv_2mortal(newSViv(len)) );
        }

int 
hasChildNodes( elem )
        SV* elem
    CODE:
        if ( PmmSvNode(elem)->type == XML_ATTRIBUTE_NODE ) {
            RETVAL = 0;
        }
        else {
            RETVAL =  PmmSvNode(elem)->children ? 1 : 0 ;
        }
    OUTPUT:
        RETVAL

int 
hasAttributes( elem )
        SV* elem
    CODE:
        if ( PmmSvNode(elem)->type == XML_ATTRIBUTE_NODE ) {
            RETVAL = 0;
        }
        else {
            RETVAL =  PmmSvNode(elem)->properties ? 1 : 0 ;
        }
    OUTPUT:
        RETVAL

SV*
ownerDocument( elem )
        SV* elem
    ALIAS:
        XML::LibXML::Node::getOwnerDocument = 1
    PREINIT:
        xmlNodePtr self = PmmSvNode(elem);
    CODE:
        xs_warn( "GET OWNERDOC\n" );
        if( self != NULL
            && self->doc != NULL
            && PmmSvOwner(elem) != NULL ){
            RETVAL = PmmNodeToSv((xmlNodePtr)(self->doc), NULL);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
ownerNode( elem ) 
        SV* elem
    ALIAS:
        XML::LibXML::Node::getOwner = 1
        XML::LibXML::Node::getOwnerElement = 2
    CODE:
        if( PmmSvOwner(elem) != NULL ){
            RETVAL = PmmNodeToSv(PmmSvOwner(elem), NULL);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL


int
normalize( self )
        SV * self
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
    CODE:
        RETVAL = domNodeNormalize( node );
    OUTPUT:
        RETVAL


SV*
insertBefore( self, new, ref ) 
        SV* self
        SV* new
        SV* ref
    PREINIT:
        xmlNodePtr pNode, nNode, oNode, rNode;
    CODE:
        if ( new == NULL
           || new == &PL_sv_undef ){
            XSRETURN_UNDEF;
        }
        else {
            pNode = PmmSvNode(self);
            nNode = PmmSvNode(new);
            oNode = PmmSvNode(ref); /* may is NULL */
   
            if ( pNode->type    == XML_DOCUMENT_NODE
                 && nNode->type == XML_ELEMENT_NODE ) {
                xs_warn( "NOT_SUPPORTED_ERR\n" );
                XSRETURN_UNDEF;
            }
            else {
                rNode = domInsertBefore( pNode, nNode, oNode );
                if ( rNode != NULL ) {
                    RETVAL = PmmNodeToSv( rNode,
                                          PmmOWNERPO(SvPROXYNODE(self)) );
                    PmmFixOwner(PmmOWNERPO(SvPROXYNODE(RETVAL)),
                                PmmOWNERPO(SvPROXYNODE(self)) );
                }
                else {
                    XSRETURN_UNDEF;
                }
            }
        }
    OUTPUT:
        RETVAL

SV* 
insertAfter( self, new, ref )
        SV* self
        SV* new
        SV* ref
    PREINIT:
        xmlNodePtr pNode, nNode, oNode, rNode;
    CODE:
        if ( new == NULL
           || new == &PL_sv_undef ){
            XSRETURN_UNDEF;
        }
        else {            
            pNode = PmmSvNode(self);
            nNode = PmmSvNode(new);
            oNode = PmmSvNode(ref); /* may be null */

            if ( pNode->type    == XML_DOCUMENT_NODE
                 && nNode->type == XML_ELEMENT_NODE ) {
                xs_warn( "NOT_SUPPORTED_ERR\n" );
                XSRETURN_UNDEF;
            }
            else {
                rNode = domInsertAfter( pNode, nNode, oNode );
                if ( rNode != NULL ) {
                    RETVAL = PmmNodeToSv( rNode,
                                          PmmOWNERPO(SvPROXYNODE(self)) );
                    PmmFixOwner(PmmOWNERPO(SvPROXYNODE(RETVAL)),
                                PmmOWNERPO(SvPROXYNODE(self)) );
                }
                else {
                    XSRETURN_UNDEF;
                }
            }
        }
    OUTPUT:
        RETVAL

SV*
replaceChild( paren, newChild, oldChild ) 
        SV* paren
        SV* newChild
        SV* oldChild
    PREINIT:
        ProxyNodePtr docfrag;
        xmlNodePtr pNode, nNode, oNode;
        xmlNodePtr ret;
    CODE:
        if ( newChild  == NULL
           || newChild == &PL_sv_undef
           || oldChild == NULL
           || oldChild == &PL_sv_undef ) {
            XSRETURN_UNDEF;
        }
        else {            
            pNode = PmmSvNode( paren );
            nNode = PmmSvNode( newChild );
            oNode = PmmSvNode( oldChild );
            if ( pNode->type == XML_DOCUMENT_NODE ) {
                switch ( nNode->type ) {
                case XML_ELEMENT_NODE:
                case XML_DOCUMENT_FRAG_NODE:
                case XML_TEXT_NODE:
                case XML_CDATA_SECTION_NODE:
                    XSRETURN_UNDEF;
                    break;
                default:
                    break;
                }
            }
            ret = domReplaceChild( pNode, nNode, oNode );
            if (ret == NULL) {
                XSRETURN_UNDEF;
            }
            else {
                /* create document fragment */
                docfrag = PmmNewFragment( pNode->doc );
                domAppendChild( PmmNODE(docfrag), ret );

                RETVAL = PmmNodeToSv(ret, NULL);
                if ( nNode->_private != NULL ) {
                    PmmFixOwner( SvPROXYNODE(newChild),
                                 PmmOWNERPO(SvPROXYNODE(paren)) );
                }
                PmmFixOwner( SvPROXYNODE(RETVAL),
                             docfrag );
            }
        }
    OUTPUT:
        RETVAL

SV* 
replaceNode( self,newNode )
        SV * self
        SV * newNode
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
        xmlNodePtr other = PmmSvNode( newNode );
        xmlNodePtr ret = NULL;
    CODE:
        if ( other == NULL || domIsParent( node, other ) == 1 ) {
            XSRETURN_UNDEF;
        }
        if ( node->doc != other->doc ) {
            domImportNode( node->doc, other, 1 );
        }
        ret = xmlReplaceNode( node, other );
        if ( ret ) {
            ProxyNodePtr docfrag = PmmNewFragment( node->doc );
            domAppendChild( PmmNODE(docfrag), ret );
            RETVAL = PmmNodeToSv(ret,docfrag);
            if ( other->_private != NULL ) {
                PmmFixOwner( SvPROXYNODE(newNode),
                             PmmOWNERPO(SvPROXYNODE(self)));
            }
            PmmFixOwner( SvPROXYNODE(RETVAL), docfrag );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
removeChild( pparen, child ) 
        SV*  pparen
        SV* child
    PREINIT:
        xmlNodePtr paren, ret;
        ProxyNodePtr docfrag;
    CODE:
        if ( pparen == NULL
             || pparen == &PL_sv_undef
             || child == NULL
             || child == &PL_sv_undef ) {
            XSRETURN_UNDEF;
        }
        else {
            paren = PmmSvNode( pparen );
            ret = domRemoveChild( paren, PmmSvNode(child) );
            if (ret == NULL) {
                XSRETURN_UNDEF;
            }
            else {
                docfrag = PmmNewFragment(paren->doc );
                domAppendChild( PmmNODE(docfrag), ret );
                RETVAL = PmmNodeToSv(ret,docfrag);
                PmmFixOwner( SvPROXYNODE(RETVAL), docfrag );
            }
        }
    OUTPUT:
        RETVAL

void
removeChildNodes( pparen )
        SV * pparen
    PREINIT:
        xmlNodePtr paren, elem, fragment;
        ProxyNodePtr docfrag;
    INIT:
        if ( pparen == NULL
             || pparen == &PL_sv_undef ) {
            XSRETURN_UNDEF;
        }
        paren = PmmSvNode( pparen );
        if ( paren == NULL ) {
            croak( "In Scalar there was no node" );
            XSRETURN_UNDEF;
        }
    CODE:
        docfrag  = PmmNewFragment( paren->doc );
        fragment = PmmNODE( docfrag );
        elem = paren->children;
        while ( elem ) {
            xmlUnlinkNode( elem );
            if ( elem->type != XML_ATTRIBUTE_NODE ) {
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
            }
            PmmFixOwnerNode( elem, docfrag );
            elem = elem->next;
        }

        paren->children = paren->last = NULL;
        if ( PmmREFCNT(docfrag) <= 0 ) {
            xs_warn( "have not references left" );
            PmmREFCNT_dec( docfrag );
        }

void
unbindNode( proxyelem )
        SV* proxyelem
    PREINIT:
        xmlNodePtr elem       = NULL;
        ProxyNodePtr dfProxy = NULL;
    INIT:
        elem = PmmSvNode(proxyelem);
        if ( elem == NULL ) {
            XSRETURN_UNDEF;
        }
    CODE:
        if ( elem->type != XML_DOCUMENT_NODE
             || elem->type != XML_DOCUMENT_FRAG_NODE ) {
            if ( elem->type != XML_ATTRIBUTE_NODE ) {
                if ( elem->doc != NULL ) 
                    dfProxy = PmmNewFragment(elem->doc);
                else 
                    dfProxy = PmmNewFragment(NULL);
            }
            xmlUnlinkNode( elem );
            if ( elem->type != XML_ATTRIBUTE_NODE ) {
                domAppendChild( PmmNODE(dfProxy), elem );
            }
            PmmFixOwner( SvPROXYNODE(proxyelem), dfProxy );
        }

SV*
appendChild( parent, child )
        SV* parent
        SV* child
    PREINIT:
        ProxyNodePtr pproxy = NULL;
        ProxyNodePtr cproxy = NULL;
        xmlNodePtr test = NULL, pNode, cNode, rNode;
    CODE:
        pNode = PmmSvNode(parent);
        cNode = PmmSvNode(child);

        if ( pNode == NULL
            || cNode == NULL ) {
            XSRETURN_UNDEF;
        }
        else {
            if (pNode->type == XML_DOCUMENT_NODE ) {
                /* NOT_SUPPORTED_ERR
                 */
                switch ( cNode->type ) {
                case XML_ELEMENT_NODE:
                case XML_DOCUMENT_FRAG_NODE:
                case XML_TEXT_NODE:
                case XML_CDATA_SECTION_NODE:
                    XSRETURN_UNDEF;
                    break;
                default:
                    break;
                }
            }
            rNode = domAppendChild( pNode, cNode );
            if ( rNode == NULL ) {
                XSRETURN_UNDEF;
            }
           
            RETVAL = PmmNodeToSv( cNode,
                                  PmmOWNERPO(SvPROXYNODE(parent)) );
            PmmFixOwner( SvPROXYNODE(RETVAL), SvPROXYNODE(parent) );
        }
    OUTPUT:
        RETVAL

SV*
addSibling( self, newNode )
        SV * self
        SV * newNode
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
        xmlNodePtr other = PmmSvNode( newNode );
        xmlNodePtr ret = NULL;
        ProxyNodePtr oproxy = SvPROXYNODE( newNode ); 
    CODE:
        if ( other == NULL || other->type == XML_DOCUMENT_FRAG_NODE ) {
            XSRETURN_UNDEF;
        }
        ret = xmlAddSibling( node, other );
        if ( ret ) {
            RETVAL = PmmNodeToSv(ret,NULL);
            PmmFixOwner( SvPROXYNODE(RETVAL), PmmOWNERPO(SvPROXYNODE(self)) );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV*
cloneNode( self, deep=0 ) 
        SV* self
        int deep
    PREINIT:
        xmlNodePtr ret, node;
        xmlDocPtr doc;
        ProxyNodePtr docfrag = NULL;
    CODE:
        node = PmmSvNode( self );
        ret = PmmCloneNode( node, deep );
        if ( ret == NULL ) {
            XSRETURN_UNDEF;
        }

        if ( ret->type  == XML_DTD_NODE ) {
            RETVAL = PmmNodeToSv(ret, NULL);
        }
        else {
            doc = node->doc;
            
            if ( doc != NULL ) {
                xmlSetTreeDoc(ret, doc);
            }

            # make namespaces available
            ret->ns = node->ns;

            xmlReconciliateNs(ret->doc, ret);     

            docfrag = PmmNewFragment( ret->doc );
            domAppendChild( PmmNODE(docfrag), ret );            
            
            RETVAL = PmmNodeToSv(ret, docfrag);
        }   
    OUTPUT:
        RETVAL

int 
isSameNode( self, other )
        SV * self
        SV * other
    ALIAS:
        XML::LibXML::Node::isEqual = 1
    PREINIT:
        xmlNodePtr thisnode = PmmNODE(SvPROXYNODE(self));
        xmlNodePtr thatnode = PmmNODE(SvPROXYNODE(other));
    CODE:
        RETVAL = 0;
        if( thisnode == thatnode ) {
            RETVAL = 1;
        }
    OUTPUT:
        RETVAL

SV *
baseURI( self )
        SV * self
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
        xmlChar * uri;
    CODE:
        uri = xmlNodeGetBase( node->doc, node );
        RETVAL = C2Sv( uri, NULL );
        xmlFree( uri );
    OUTPUT:
        RETVAL

void
setBaseURI( self, URI )
        SV * self
        SV * URI
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
        xmlChar * uri;
    CODE:
        uri = nodeSv2C( URI, node );
        if ( uri != NULL ) {
            xmlNodeSetBase( node, uri );
        }

SV*
toString( self, format=0, useDomEncoding = &PL_sv_undef )
        SV * self
        SV * useDomEncoding
        int format
    PREINIT:
        xmlBufferPtr buffer;
        char *ret = NULL;
        SV* internalFlag = NULL;
        int oldTagFlag = xmlSaveNoEmptyTags;
    CODE:
        internalFlag = perl_get_sv("XML::LibXML::setTagCompression", 0);

        if ( internalFlag ) {
            xmlSaveNoEmptyTags = SvTRUE(internalFlag);
        }
        buffer = xmlBufferCreate();
        if ( format <= 0 ) {
            xmlNodeDump( buffer,
                         PmmNODE(SvPROXYNODE(self))->doc,
                         PmmNODE(SvPROXYNODE(self)), 0, format);
        }
        else {
            int t_indent_var = xmlIndentTreeOutput;
            xmlIndentTreeOutput = 1;
            xmlNodeDump( buffer,
                         PmmNODE(SvPROXYNODE(self))->doc,
                         PmmNODE(SvPROXYNODE(self)), 0, format);
            xmlIndentTreeOutput = t_indent_var;
        }
        if ( buffer->content != 0 ) {
            ret= xmlStrdup( buffer->content );
        }
        
        xmlBufferFree( buffer );
        xmlSaveNoEmptyTags = oldTagFlag;

        if ( ret != NULL ) {
            if ( useDomEncoding!= &PL_sv_undef && SvTRUE(useDomEncoding) ) {
                RETVAL = nodeC2Sv(ret, PmmNODE(SvPROXYNODE(self))) ;
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

SV*
string_value ( node, useDomEncoding = &PL_sv_undef )
        SV * node
        SV * useDomEncoding
    ALIAS:
        to_literal = 1
        textContent = 2
    PREINIT:
         xmlChar * string = NULL;
    CODE:
        /* we can't just return a string, because of UTF8! */
        string = xmlXPathCastNodeToString(PmmSvNode(node));
        if ( SvTRUE(useDomEncoding) ) {
            RETVAL = nodeC2Sv(string,
                              PmmSvNode(node));
        }
        else {
            RETVAL = C2Sv(string,
                          NULL);
        }
        xmlFree(string);
    OUTPUT:
        RETVAL

double
to_number ( node )
        SV* node
    CODE:
        RETVAL = xmlXPathCastNodeToNumber(PmmNODE(SvPROXYNODE(node)));
    OUTPUT:
        RETVAL

void
_find( pnode, pxpath )
        SV* pnode
        SV * pxpath
    PREINIT:
        xmlNodePtr node = PmmSvNode(pnode);
        ProxyNodePtr owner = NULL;
        xmlXPathObjectPtr found = NULL;
        xmlNodeSetPtr nodelist = NULL;
        SV* element = NULL ;
        int len = 0 ;
        xmlChar * xpath = nodeSv2C(pxpath, node);
    INIT:
        if ( !(xpath && xmlStrlen(xpath)) ) {
            xs_warn( "bad xpath\n" );
            if ( xpath ) 
                xmlFree(xpath);
            croak( "empty XPath found" );
            XSRETURN_UNDEF;
        }
    PPCODE:
        if ( node->doc ) {
            domNodeNormalize( xmlDocGetRootElement( node->doc ) );
        }
        else {
            domNodeNormalize( PmmOWNER(SvPROXYNODE(pnode)) );
        }

        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);
        xmlSetGenericErrorFunc(PerlIO_stderr(), 
                               (xmlGenericErrorFunc)LibXML_error_handler);

        found = domXPathFind( node, xpath );
        xmlFree( xpath );

        xmlSetGenericErrorFunc(NULL, NULL);
        
        sv_2mortal( LibXML_error );

        if ( SvCUR( LibXML_error ) > 0 ) {
            croak(SvPV(LibXML_error, len));
        }

        if (found) {
            switch (found->type) {
                case XPATH_NODESET:
                    /* return as a NodeList */
                    /* access ->nodesetval */
                    XPUSHs(sv_2mortal(newSVpv("XML::LibXML::NodeList", 0)));
                    nodelist = found->nodesetval;
                    if ( nodelist ) {
                        if ( nodelist->nodeNr > 0 ) {
                            int i = 0 ;
                            const char * cls = "XML::LibXML::Node";
                            xmlNodePtr tnode;
                            SV * element;
                        
                            owner = PmmOWNERPO(SvPROXYNODE(pnode));
                            len = nodelist->nodeNr;
                            for( i ; i < len; i++){
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
        }
        else {
            if ( SvCUR( LibXML_error ) > 0 ) {
                croak(SvPV(LibXML_error, len));
            }
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
        int len = 0 ;
        xmlChar * xpath = nodeSv2C(perl_xpath, node);
    INIT:
        if ( !(xpath && xmlStrlen(xpath)) ) {
            xs_warn( "bad xpath\n" );
            if ( xpath ) 
                xmlFree(xpath);
            croak( "empty XPath found" );
            XSRETURN_UNDEF;
        }
    PPCODE:
        if ( node->doc ) {
            domNodeNormalize( xmlDocGetRootElement(node->doc ) );
        }
        else {
            domNodeNormalize( PmmOWNER(SvPROXYNODE(pnode)) );
        }

        LibXML_error = NEWSV(0, 512);
        sv_setpvn(LibXML_error, "", 0);
        xmlSetGenericErrorFunc(PerlIO_stderr(), 
                               (xmlGenericErrorFunc)LibXML_error_handler);

        nodelist = domXPathSelect( node, xpath );
        xmlFree(xpath);
        xmlSetGenericErrorFunc(NULL, NULL);

        sv_2mortal( LibXML_error );

        if ( SvCUR( LibXML_error ) > 0 ) {
            croak(SvPV(LibXML_error, len));
        }

        if ( nodelist ) {
            if ( nodelist->nodeNr > 0 ) {
                int i = 0 ;
                const char * cls = "XML::LibXML::Node";
                xmlNodePtr tnode;
                owner = PmmOWNERPO(SvPROXYNODE(pnode));
                len = nodelist->nodeNr;
                for( i ; i < len; i++){
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
        }
        else {
            if ( SvCUR( LibXML_error ) > 0 ) {
                croak(SvPV(LibXML_error, len));
            }
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
        SV* element;
        const char * class = "XML::LibXML::Namespace";
    PPCODE:
        node = PmmSvNode(pnode);
        ns = node->nsDef;
        while ( ns != NULL ) {
            newns = xmlCopyNamespace(ns);
            if ( newns != NULL ) {
                element = NEWSV(0,0);
                element = sv_setref_pv( element,
                                        (const char *)class,
                                        (void*)newns
                                      );
                XPUSHs( sv_2mortal(element) );
            }
            ns = ns->next;
        }

SV *
getNamespace( pnode )
        SV * pnode
    ALIAS:  
        localNamespace = 1
        localNS        = 2
    PREINIT:
        xmlNodePtr node;
        xmlNsPtr ns = NULL;
        xmlNsPtr newns = NULL;
        const char * class = "XML::LibXML::Namespace";
    CODE:
        node = PmmSvNode(pnode);
        ns = node->ns;
        if ( ns != NULL ) {
            newns = xmlCopyNamespace(ns);
            if ( newns != NULL ) {
                RETVAL = NEWSV(0,0);
                RETVAL = sv_setref_pv( RETVAL,
                                       (const char *)class,
                                       (void*)newns
                                      );
            }
        }
    OUTPUT:
        RETVAL
        
MODULE = XML::LibXML         PACKAGE = XML::LibXML::Element

SV*
new(CLASS, name )
        char * CLASS
        char * name
    PREINIT:
        xmlNodePtr newNode;
        ProxyNodePtr dfProxy;
    CODE:
        dfProxy = PmmNewFragment(NULL);
        newNode = xmlNewNode( NULL, name );
        newNode->doc = NULL;
        domAppendChild(PmmNODE(dfProxy), newNode);
        RETVAL = PmmNodeToSv(newNode, dfProxy );
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
    CODE:
        if ( !nsURI ){
            XSRETURN_UNDEF;
        }

        nsPrefix = nodeSv2C(namespacePrefix, node);
        if ( ns = xmlSearchNsByHref(node->doc, node, nsURI) ) {
            if ( ns->prefix == nsPrefix               /* both are NULL then */
                 || xmlStrEqual( ns->prefix, nsPrefix ) ) {            
                RETVAL = 1;
            }
            else if ( ns = xmlNewNs( node, nsURI, nsPrefix ) ) {
                RETVAL = 1;
            }
            else {
                RETVAL = 0;
            }
        }
        else if ( ns = xmlNewNs( node, nsURI, nsPrefix ) )
            RETVAL = 1;
        else
            RETVAL = 0;

        if ( flag && ns )
            node->ns = ns;

        xmlFree(nsPrefix);
        xmlFree(nsURI);
    OUTPUT:
        RETVAL

int 
hasAttribute( self, attr_name )
        SV * self
        SV * attr_name
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
        xmlChar * name = nodeSv2C(attr_name, node );
    CODE:
        if ( ! name ) {
            XSRETURN_UNDEF;
        }
        if ( xmlHasProp( node, name ) ) {
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
        SV * self
        SV * namespaceURI
        SV * attr_name
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
        xmlChar * name = nodeSv2C(attr_name, node );
        xmlChar * nsURI = nodeSv2C(namespaceURI, node );
    CODE:
        if ( !name ) {
            xmlFree(nsURI);
            XSRETURN_UNDEF;
        }
        if ( !nsURI ){
            xmlFree(name);
            XSRETURN_UNDEF;
        }
        if ( xmlHasNsProp( node, name, nsURI ) ) {
            RETVAL = 1;
        }
        else {
            RETVAL = 0;
        }

        xmlFree(name);
        xmlFree(nsURI);        
    OUTPUT:
        RETVAL

SV*
getAttribute( self, attr_name )
        SV * self
        SV * attr_name
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
        xmlChar * name = nodeSv2C(attr_name, node );
        xmlChar * ret = NULL;
    CODE:
        if( !name ) {
            XSRETURN_UNDEF;
        }
        
        ret = xmlGetProp(node, name);
        xmlFree(name);

        if ( ret ) {
            RETVAL = nodeC2Sv(ret, node);
            xmlFree( ret );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

void
_setAttribute( self, attr_name, attr_value )
        SV * self
        SV * attr_name
        SV * attr_value
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
        xmlChar * name  = nodeSv2C(attr_name, node );
        xmlChar * value = NULL;
    CODE:
        if ( !name ) {
            XSRETURN_UNDEF;
        }
        value = nodeSv2C(attr_value, node );
       
        xmlSetProp( node, name, value );
        xmlFree(name);
        xmlFree(value);        


void
removeAttribute( self, attr_name )
        SV * self
        SV * attr_name
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
        xmlChar * name  = nodeSv2C(attr_name, node );
        xmlAttrPtr xattr = NULL;
    CODE:
        if ( name ) {
            xattr = xmlHasProp( node, name );

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
        SV * self
        SV * attr_name
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
        xmlChar * name = nodeSv2C(attr_name, node );
        xmlAttrPtr ret = NULL;
    CODE:
        if ( !name ) {
            XSRETURN_UNDEF;
        }

        ret = xmlHasProp( node, name );
        xmlFree(name);

        if ( ret ) {
            RETVAL = PmmNodeToSv( (xmlNodePtr)ret,
                                   PmmOWNERPO(SvPROXYNODE(self)) );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV *
setAttributeNode( self, attr_node )
        SV * self
        SV * attr_node
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
        xmlAttrPtr attr = (xmlAttrPtr)PmmSvNode( attr_node );
        xmlAttrPtr ret = NULL;
    CODE:
        if ( attr != NULL && attr->type != XML_ATTRIBUTE_NODE ) {
            XSRETURN_UNDEF;
        }
        if ( attr->doc != node->doc ) {
            domImportNode( node->doc, (xmlNodePtr)attr, 1);
        }
        ret = xmlHasProp( node, attr->name );
        if ( ret != NULL ) {
            if ( ret != attr ) {
                xmlReplaceNode( (xmlNodePtr)ret, (xmlNodePtr)attr );
            }
            else {
                XSRETURN_UNDEF;
            }
        }
        else {
            xmlAddChild( node, (xmlNodePtr)attr );
        }

        if ( attr->_private != NULL ) {
            PmmFixOwner( SvPROXYNODE(attr_node), SvPROXYNODE(self) );
        }

        if ( ret == NULL ) {
            XSRETURN_UNDEF;
        }

        RETVAL = PmmNodeToSv( (xmlNodePtr)ret, NULL );
        PmmFixOwner( SvPROXYNODE(RETVAL), NULL );
    OUTPUT:
        RETVAL

SV *
getAttributeNS( self, namespaceURI, attr_name )
        SV * self
        SV * namespaceURI
        SV * attr_name
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
        xmlChar * name = nodeSv2C( attr_name, node );
        xmlChar * nsURI = nodeSv2C( namespaceURI, node );
        xmlChar * ret = NULL;
    CODE:
        if ( !name ) {
            xmlFree(nsURI);
            XSRETURN_UNDEF;
        }
        if ( nsURI && xmlStrlen(nsURI) ) {     
            ret = xmlGetNsProp( node, name, nsURI );
        }
        else {
            ret = xmlGetProp( node, name );
        }

        xmlFree( name );
        if ( nsURI ) {
            xmlFree( nsURI );
        }
        if ( ret ) {
            RETVAL = nodeC2Sv( ret, node );
            xmlFree( ret );
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

void
setAttributeNS( self, namespaceURI, attr_name, attr_value )
        SV * self
        SV * namespaceURI
        SV * attr_name
        SV * attr_value
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
        xmlChar * nsURI = nodeSv2C( namespaceURI, node );
        xmlChar * name  = NULL;
        xmlChar * value = NULL;
        const xmlChar * pchar = NULL;
        xmlNsPtr ns         = NULL;
        xmlChar * localname = NULL;
        xmlChar * prefix    = NULL;
    INIT:
        name  = nodeSv2C( attr_name, node );        
        if ( !name && !xmlStrlen( name ) ) {
            if ( nsURI ) {
                xmlFree( nsURI);
            }
            croak( "no name" );
            XSRETURN_UNDEF;
        }
        localname = xmlSplitQName2(name, &prefix); 
        if ( localname ) {
            xmlFree( name ); 
            name = localname;
        }
    CODE:
        value = nodeSv2C( attr_value, node ); 

        if ( nsURI && xmlStrlen(nsURI) ) {
            xs_warn( "found uri" );

            ns = xmlSearchNsByHref( node->doc, node, nsURI );
            if ( !ns ) {
                /* create new ns */
                 if ( prefix && xmlStrlen( prefix ) ) {
                    ns = xmlNewNs(node, nsURI , prefix );
                 }
                 else {
                    ns = NULL;
                 }
            }
            else if ( !ns->prefix ) {
                if ( ns->next && ns->next->prefix ) {
                    ns = ns->next;
                }
                else if ( prefix && xmlStrlen( prefix ) ) {
                    ns = xmlNewNs(node, nsURI , prefix );
                }
                else {
                    ns = NULL;
                }
            }
        }

        if ( nsURI && xmlStrlen(nsURI) && !ns ) {
            xs_warn( "bad ns attribute!" );
        }
        else {
            /* warn( "set attribute %s->%s", name, value ); */
            xmlSetNsProp( node, ns, name, value );            
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
        SV * self
        SV * namespaceURI
        SV * attr_name
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
        xmlChar * nsURI = nodeSv2C( namespaceURI, node );
        xmlChar * name  = NULL;
        xmlAttrPtr xattr = NULL;
    CODE:
        name  = nodeSv2C( attr_name, node );
        if ( ! name ) {
            xmlFree(nsURI);
            XSRETURN_UNDEF;
        }

        if ( nsURI && xmlStrlen(nsURI) ) {
            xattr = xmlHasNsProp( node, name, nsURI );
        }
        else {
            xattr = xmlHasNsProp( node, name, NULL );
        }
        if ( xattr ) {
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
        SV * self
        SV * namespaceURI
        SV * attr_name
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
        xmlChar * nsURI = nodeSv2C(namespaceURI, node );
        xmlChar * name = nodeSv2C(attr_name, node );
        xmlAttrPtr ret = NULL;
    CODE:
        if ( !name ) {
            xmlFree(nsURI);
            XSRETURN_UNDEF;
        }
        if ( !nsURI ){
            xmlFree(name);
            XSRETURN_UNDEF;
        }

        ret = xmlHasNsProp( node, name, nsURI );
        xmlFree(name);
        xmlFree(nsURI);        

        if ( ret ) {
            RETVAL = PmmNodeToSv( (xmlNodePtr)ret,
                                   PmmOWNERPO(SvPROXYNODE(self)) );
        }
        else {
            /* warn("no prop\n"); */
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV *
setAttributeNodeNS( self, attr_node )
        SV * self
        SV * attr_node
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
        xmlAttrPtr attr = (xmlAttrPtr)PmmSvNode( attr_node );
        xmlNsPtr ns = NULL;
        xmlAttrPtr ret = NULL;
    CODE:
        if ( attr != NULL && attr->type != XML_ATTRIBUTE_NODE ) {
            XSRETURN_UNDEF;
        }

        if ( attr->doc != node->doc ) {
            domImportNode( node->doc, (xmlNodePtr)attr, 1);
        }


        ns = attr->ns;
        if ( ns != NULL ) {
            ret = xmlHasNsProp( node, ns->href, attr->name );
        }
        else {
            ret = xmlHasProp( node, attr->name );
        }

        if ( ret != NULL ) {
            if ( ret != attr ) {
                xmlReplaceNode( (xmlNodePtr)ret, (xmlNodePtr)attr );
            }
            else {
                XSRETURN_UNDEF;
            }
        }
        else {
            xmlAddChild( node, (xmlNodePtr)attr );
            xmlReconciliateNs(node->doc, node);
        }
        if ( attr->_private != NULL ) {
            PmmFixOwner( SvPROXYNODE(attr_node), SvPROXYNODE(self) );
        }
        if ( ret == NULL ) {
            XSRETURN_UNDEF;
        }
        RETVAL = PmmNodeToSv( (xmlNodePtr)ret, NULL );
        PmmFixOwner( SvPROXYNODE(RETVAL), NULL );
    OUTPUT:
        RETVAL

SV *
removeAttributeNode( self, attr_node )
        SV * self
        SV * attr_node
    PREINIT:
        xmlNodePtr node = PmmSvNode( self );
        xmlAttrPtr attr = (xmlAttrPtr)PmmSvNode( attr_node );
        xmlAttrPtr ret;
    CODE:
        if ( attr == NULL || attr->type != XML_ATTRIBUTE_NODE ) {
            XSRETURN_UNDEF;
        }
        if ( attr->parent != node ) {
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
        SV * self
        SV * string
    ALIAS:
        appendTextNode = 1
        XML::LibXML::DocumentFragment::appendText = 2
        XML::LibXML::DocumentFragment::appendTextNode = 3
    PREINIT:
        xmlNodePtr node   = PmmSvNode( self );
        xmlChar * content = nodeSv2C( string, node );
    INIT:
        if ( content == NULL ) {
            XSRETURN_UNDEF;
        }
        if ( xmlStrlen(content) == 0 ) {
            xmlFree( content );
            XSRETURN_UNDEF;
        }
    CODE:
        xmlNodeAddContent( node, content );
        xmlFree(content);

void
appendTextChild( self, strname, strcontent=&PL_sv_undef, nsURI=&PL_sv_undef )
        SV * self
        SV * strname
        SV * strcontent
        SV * nsURI
    PREINIT:
        xmlNodePtr node   = PmmSvNode( self );
        xmlChar * name    = nodeSv2C( strname, node );
        xmlChar * content = NULL;
        xmlChar * encstr  = NULL;
    INIT:
        if ( name == NULL ) {
            XSRETURN_UNDEF;
        }
        if ( xmlStrlen(name) == 0 ) {
            xmlFree(name);
            XSRETURN_UNDEF;
        }
    CODE: 
        content = nodeSv2C(strcontent, node);
        if ( content &&  xmlStrlen( content ) == 0 ) {
            xmlFree(content);
            content=NULL;
        }
        else if ( content ) {
            encstr = xmlEncodeEntitiesReentrant( node->doc, content );
            xmlFree(content);
        }

        xmlNewChild( node, NULL, name, encstr );

        if ( encstr ) 
            xmlFree(encstr);
        xmlFree(name);


MODULE = XML::LibXML         PACKAGE = XML::LibXML::Text

SV *
new( CLASS, content )
        const char * CLASS
        SV * content
    PREINIT:
        xmlChar * data;
        xmlNodePtr newNode;
    CODE:
        data = Sv2C(content, NULL);
        newNode = xmlNewText( data );
        xmlFree(data);
        if( newNode != NULL ) {
            RETVAL = PmmNodeToSv(newNode,NULL);
        }
        else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL

SV *
substringData( perlnode, offset, length ) 
        SV * perlnode
        int offset
        int length
    PREINIT:
        xmlChar * data = NULL;
        xmlChar * substr = NULL;
        int len = 0;
        int dl = 0;
        xmlNodePtr node = PmmSvNode( perlnode );
    CODE:
        if ( node != NULL && offset >= 0 && length > 0 ) {
            dl = offset + length - 1 ;
            data = domGetNodeValue( node );
            len = xmlStrlen( data );
            if ( data != NULL && len > 0 && len > offset ) {
                if ( dl > len ) 
                    dl = offset + len;

                substr = xmlStrsub( data, offset, dl );
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
setData( perlnode, value )
        SV * perlnode
        SV * value
    ALIAS:
        XML::LibXML::Attr::setValue = 1 
        XML::LibXML::PI::_setData = 2
    PREINIT:
        xmlChar * encstr = NULL;
        xmlNodePtr node = PmmSvNode(perlnode);
    CODE:
        if ( node != NULL ) {
            encstr = nodeSv2C(value,node);
            domSetNodeValue( node, encstr );
            xmlFree(encstr);
        }

void 
appendData( perlnode, value )
        SV * perlnode
        SV * value
    PREINIT:
        xmlChar * data = NULL;
        xmlChar * encstring = NULL;
        xmlNodePtr node = PmmSvNode(perlnode);
        int strlen = 0;
    CODE:
        if ( node != NULL ) {
            encstring = Sv2C( value,
                              node->doc!=NULL ? node->doc->encoding : NULL );
            
            if ( encstring != NULL ) {
                strlen = xmlStrlen( encstring );
                xmlTextConcat( node, encstring, strlen );
                xmlFree( encstring );
            }
        }

void
insertData( perlnode, offset, value ) 
        SV * perlnode
        int offset
        SV * value
    PREINIT:
        xmlChar * after= NULL;
        xmlChar * data = NULL;
        xmlChar * new  = NULL;
        xmlChar * encstring = NULL;
        int dl = 0;
        xmlNodePtr node = PmmSvNode(perlnode);
    CODE:
        if ( node != NULL && offset >= 0 ) {
            encstring = Sv2C( value,
                              node->doc!=NULL ? node->doc->encoding : NULL );
            if ( encstring != NULL && xmlStrlen( encstring ) > 0 ) {
                data = domGetNodeValue(node);
                if ( data != NULL && xmlStrlen( data ) > 0 ) {
                    if ( xmlStrlen( data ) < offset ) {
                        data = xmlStrcat( data, encstring );
                        domSetNodeValue( node, data );
                    }
                    else {
                        dl = xmlStrlen( data ) - offset;

                        if ( offset > 0 )
                            new   = xmlStrsub(data, 0, offset );

                        after = xmlStrsub(data, offset, dl );

                        if ( new != NULL ) {
                            new = xmlStrcat(new, encstring );
                        }
                        else {
                            new = xmlStrdup( encstring );
                        }

                        if ( after != NULL ) 
                            new = xmlStrcat(new, after );
    
                        domSetNodeValue( node, new );

                        xmlFree( new );
                        xmlFree( after );
                    }
                    xmlFree( data );
                }
                else {
                    domSetNodeValue( node, encstring );
                }
                xmlFree(encstring);
            }
        }

void
deleteData( perlnode, offset, length )
        SV * perlnode
        int offset
        int length
    PREINIT:
        xmlChar * data  = NULL;
        xmlChar * after = NULL;
        xmlChar * new   = NULL;
        int len = 0;
        int dl1 = 0;
        int dl2 = 0;
        xmlNodePtr node = PmmSvNode(perlnode);
    CODE:
        if ( node != NULL && length > 0 && offset >= 0 ) {
            data = domGetNodeValue(node);
            len = xmlStrlen( data );
            if ( data != NULL
                 && len > 0
                 && len > offset ) {
                dl1 = offset + length;
                if ( offset > 0 )
                    new = xmlStrsub( data, 0, offset );

                if ( len > dl1 ) {
                    dl2 = len - dl1;
                    after = xmlStrsub( data, dl1, dl2 );
                    if ( new != NULL ) {
                        new = xmlStrcat( new, after );
                        xmlFree(after);
                    }
                    else {
                        new = after;
                    }
                }

                domSetNodeValue( node, new );
                xmlFree(new);
            }
        }

void
replaceData( perlnode, offset,length, value ) 
        SV * perlnode
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
        xmlNodePtr node = PmmSvNode(perlnode);
    CODE:
        if ( node != NULL && offset >= 0 ) {
            encstring = Sv2C( value,
                              node->doc!=NULL ? node->doc->encoding : NULL );

            if ( encstring != NULL && xmlStrlen( encstring ) > 0 ) {
                data = domGetNodeValue(node);
                len = xmlStrlen( data );

                if ( data != NULL
                     && len > 0
                     && len > offset  ) {

                    dl1 = offset + length;
                    if ( dl1 < len ) {
                        dl2 = xmlStrlen( data ) - dl1;
                        if ( offset > 0 ) {
                            new = xmlStrsub(data, 0, offset );
                            new = xmlStrcat(new, encstring );
                        }
                        else {
                            new   = xmlStrdup( encstring );
                        }

                        after = xmlStrsub(data, dl1, dl2 );
                        new = xmlStrcat(new, after );
    
                        domSetNodeValue( node, new );

                        xmlFree( new );
                        xmlFree( after );
                    }
                    else {
                        /* replace until end! */ 
                        if ( offset > 0 ) {
                            new = xmlStrsub(data, 0, offset );
                            new = xmlStrcat(new, encstring );
                        }
                        else {
                            new   = xmlStrdup( encstring );
                        }
                        domSetNodeValue( node, new );
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
            RETVAL = PmmNodeToSv(newNode,NULL);
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
        newNode = xmlNewCDataBlock( NULL , encstring, xmlStrlen( encstring ) );
        xmlFree(encstring);
        if ( newNode != NULL ){
            RETVAL = PmmNodeToSv(newNode,NULL);
        }
        else {
            XSRETURN_UNDEF;
        }
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
        RETVAL = PmmNodeToSv( real_dom, NULL );
    OUTPUT:
        RETVAL

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Attr

SV*
new( CLASS, pname, pvalue )
        char * CLASS
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
parentElement( attrnode )
        SV * attrnode
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

        XSRETURN_UNDEF;
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
    CODE:
        if ( !nsURI ){
            XSRETURN_UNDEF;
        }
        if ( !node->parent ) {
            XSRETURN_UNDEF;
        }
        nsPrefix = nodeSv2C(namespacePrefix, (xmlNodePtr)node);
        if ( ns = xmlSearchNsByHref(node->doc, node->parent, nsURI) )
            RETVAL = 1;
        else
            RETVAL = 0;

        if ( ns )
            node->ns = ns;

        xmlFree(nsPrefix);
        xmlFree(nsURI);
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
        nsURI = Sv2C(namespaceURI,NULL);
        if ( !nsURI ) {
            XSRETURN_UNDEF;
        }
        nsPrefix = Sv2C(namespacePrefix, NULL);
        ns = xmlNewNs(NULL, nsURI, nsPrefix);
        if ( ns ) {
            RETVAL = sv_newmortal();
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
        xmlNsPtr ns = (xmlNsPtr)SvIV(SvRV(self)); 
    CODE:
        if (ns) {
            xmlFreeNs(ns);
        }

int
nodeType(self)
        SV * self
    ALIAS:
        getType = 1
    PREINIT:
        xmlNsPtr ns = (xmlNsPtr)SvIV(SvRV(self));
    CODE:
        RETVAL = ns->type;
    OUTPUT:
        RETVAL

SV*
href(self)
        SV * self
    ALIAS:
        value = 1
        nodeValue = 2
        getData = 3
        getNamespaceURI = 4
    PREINIT:
        xmlNsPtr ns = (xmlNsPtr)SvIV(SvRV(self));
        xmlChar * href;
    CODE:
        href = xmlStrdup(ns->href);
        RETVAL = C2Sv(href, NULL);
        xmlFree(href);
    OUTPUT:
        RETVAL

SV*
localname(self)
        SV * self
    ALIAS:
        name = 1
        getLocalName = 2
        getName = 3 
        getPrefix = 4
    PREINIT:
        xmlNsPtr ns = (xmlNsPtr)SvIV(SvRV(self));
        xmlChar * prefix;
    CODE:
        prefix = xmlStrdup(ns->prefix);
        RETVAL = C2Sv(prefix, NULL);
        xmlFree(prefix);
    OUTPUT:
        RETVAL

int
_isEqual(self, ref)
       SV * self
       SV * ref
    PREINIT:
       xmlNsPtr ns  = (xmlNsPtr)SvIV(SvRV(self));
       xmlNsPtr ons = (xmlNsPtr)SvIV(SvRV(ref));
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
        char * CLASS
        char * external
        char * system
    ALIAS:
        parse_uri = 1
    PREINIT:
        xmlDtdPtr dtd = NULL;
    CODE:
        LibXML_error = sv_2mortal(newSVpv("", 0));
        dtd = xmlParseDTD((const xmlChar*)external, (const xmlChar*)system);
        if ( dtd == NULL ) {
            XSRETURN_UNDEF;
        }
        RETVAL = PmmNodeToSv( (xmlNodePtr) dtd, NULL );
    OUTPUT:
        RETVAL

SV *
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
        buffer = xmlAllocParserInputBuffer(enc);
        /* buffer = xmlParserInputBufferCreateMem(str, xmlStrlen(str), enc); */
        if ( !buffer)
            croak("cant create buffer!\n" );

        new_string = xmlStrdup(str);
        xmlParserInputBufferPush(buffer, strlen(new_string), new_string);

        res = xmlIOParseDTD(NULL, buffer, enc);

        /* NOTE: For some reason freeing this InputBuffer causes a segfault! */
        /* xmlFreeParserInputBuffer(buffer); */
        xmlFree(new_string);
        if (res != NULL) {
            RETVAL = PmmNodeToSv((xmlNodePtr)res, NULL);
        }
        else {
            croak("couldn't parse DTD: %s", SvPV(LibXML_error, n_a));
        }
    OUTPUT:
        RETVAL
