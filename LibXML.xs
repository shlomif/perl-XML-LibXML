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
#include <libxml/debugXML.h>
#include <libxml/xmlerror.h>
#include <libxml/xinclude.h>

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
    if (cb) {\
        if (cb != fld) {\
            sv_setsv(cb, fld);\
        }\
    }\
    else {\
        cb = newSVsv(fld);\
    }

typedef struct _ProxyObject ProxyObject;

struct _ProxyObject {
    void * object;
    SV * extra;
};

static SV * LibXML_match_cb = NULL;
static SV * LibXML_read_cb = NULL;
static SV * LibXML_open_cb = NULL;
static SV * LibXML_close_cb = NULL;
static SV * LibXML_error = NULL;

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

void
LibXML_free_all_callbacks(void)
{
    if (LibXML_match_cb) {
        SvREFCNT_dec(LibXML_match_cb);
    }
    
    if (LibXML_read_cb) {
        SvREFCNT_dec(LibXML_read_cb);
    }
    
    if (LibXML_open_cb) {
        SvREFCNT_dec(LibXML_open_cb);
    }
    
    if (LibXML_close_cb) {
        SvREFCNT_dec(LibXML_close_cb);
    }

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
    
    if (LibXML_match_cb && SvTRUE(LibXML_match_cb)) {
        int count;
        SV * res;

        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 1);
        PUSHs(sv_2mortal(newSVpv((char*)filename, 0)));
        PUTBACK;

        count = perl_call_sv(LibXML_match_cb, G_SCALAR);

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
    
    if (LibXML_open_cb && SvTRUE(LibXML_open_cb)) {
        int count;

        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 1);
        PUSHs(sv_2mortal(newSVpv((char*)filename, 0)));
        PUTBACK;

        count = perl_call_sv(LibXML_open_cb, G_SCALAR);

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
    
    SV * ctxt = (SV *)context;
    
    if (LibXML_read_cb && SvTRUE(LibXML_read_cb)) {
        int count;

        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 2);
        PUSHs(ctxt);
        PUSHs(sv_2mortal(newSViv(len)));
        PUTBACK;

        count = perl_call_sv(LibXML_read_cb, G_SCALAR);

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
    SV * ctxt = (SV *)context;
    
    if (LibXML_close_cb && SvTRUE(LibXML_close_cb)) {
        int count;

        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        EXTEND(SP, 1);
        PUSHs(ctxt);
        PUTBACK;

        count = perl_call_sv(LibXML_close_cb, G_SCALAR);

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
    char buffer[50000];
    
    buffer[0] = 0;
    
    va_start(args, msg);
    vsprintf(&buffer[strlen(buffer)], msg, args);
    va_end(args);
    
    sv_catpv(LibXML_error, buffer);
/*    croak(buffer); */
}

void
LibXML_validity_error(void * ctxt, const char * msg, ...)
{
    va_list args;
    char buffer[50000];
    
    buffer[0] = 0;
    
    va_start(args, msg);
    vsprintf(&buffer[strlen(buffer)], msg, args);
    va_end(args);
    
    sv_catpv(LibXML_error, buffer);
/*    croak(buffer); */
}

void
LibXML_validity_warning(void * ctxt, const char * msg, ...)
{
    va_list args;
    char buffer[50000];
    
    buffer[0] = 0;
    
    va_start(args, msg);
    vsprintf(&buffer[strlen(buffer)], msg, args);
    va_end(args);
    
    warn(buffer);
}

xmlParserCtxtPtr
LibXML_get_context(SV * self)
{
    SV ** ctxt_sv;
    ctxt_sv = hv_fetch((HV *)SvRV(self), "_context", 8, 0);
    if (!ctxt_sv) {
        croak("cannot fetch context!");
    }
    return (xmlParserCtxtPtr)SvIV((SV*)SvRV(*ctxt_sv));
}

int
LibXML_read_perl (SV * ioref, char * buffer, int len)
{
    dSP;
    
    int cnt;
    SV * read_results;
    STRLEN read_length;
    char * chars;
    SV * tbuff = NEWSV(0,0);
    SV * tsize = newSViv(len);
    
    ENTER;
    SAVETMPS;
    
    PUSHMARK(SP);
    EXTEND(SP, 3);
    PUSHs(ioref);
    PUSHs(tbuff);
    PUSHs(tsize);
    PUTBACK;
    
    cnt = perl_call_method("read", G_SCALAR);
    
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
LibXML_parse_stream(SV * self, SV * ioref)
{
    xmlDocPtr doc;
    xmlParserCtxtPtr ctxt;
    int well_formed;
    char buffer[1024];
    int read_length;
    int ret = -1;
    
    read_length = LibXML_read_perl(ioref, buffer, 4);
    if (read_length > 0) {
        ctxt = xmlCreatePushParserCtxt(NULL, NULL, buffer, read_length, NULL);
        ctxt->_private = (void*)self;

        while(read_length = LibXML_read_perl(ioref, buffer, 1024)) {
            xmlParseChunk(ctxt, buffer, read_length, 0);
        }
        ret = xmlParseChunk(ctxt, buffer, 0, 1);
        
        doc = ctxt->myDoc;
        well_formed = ctxt->wellFormed;

        xmlFreeParserCtxt(ctxt);
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
    xmlRegisterInputCallbacks(
            (xmlInputMatchCallback)LibXML_input_match,
            (xmlInputOpenCallback)LibXML_input_open,
            (xmlInputReadCallback)LibXML_input_read,
            (xmlInputCloseCallback)LibXML_input_close
        );
    xmlSubstituteEntitiesDefaultValue = 1;
    xmlKeepBlanksDefaultValue = 1;
    xmlSetExternalEntityLoader((xmlExternalEntityLoader)LibXML_load_external_entity);
    xmlSetGenericErrorFunc(PerlIO_stderr(), (xmlGenericErrorFunc)LibXML_error_handler);
    LibXML_error = newSVpv("", 0);
    xmlGetWarningsDefaultValue = 0;
    xmlLoadExtDtdDefaultValue = 1;

void
END()
    CODE:
        LibXML_free_all_callbacks();
        xmlCleanupParser();
        SvREFCNT_dec(LibXML_error);

SV *
match_callback(self, ...)
        SV * self
    CODE:
        if (items > 1) {
            SET_CB(LibXML_match_cb, ST(1));
        }
        else {
            RETVAL = LibXML_match_cb ? sv_2mortal(LibXML_match_cb) : &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

SV *
open_callback(self, ...)
        SV * self
    CODE:
        if (items > 1) {
            SET_CB(LibXML_open_cb, ST(1));
        }
        else {
            RETVAL = LibXML_open_cb ? sv_2mortal(LibXML_open_cb) : &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

SV *
read_callback(self, ...)
        SV * self
    CODE:
        if (items > 1) {
            SET_CB(LibXML_read_cb, ST(1));
        }
        else {
            RETVAL = LibXML_read_cb ? sv_2mortal(LibXML_read_cb) : &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

SV *
close_callback(self, ...)
        SV * self
    CODE:
        if (items > 1) {
            SET_CB(LibXML_close_cb, ST(1));
        }
        else {
            RETVAL = LibXML_close_cb ? sv_2mortal(LibXML_close_cb) : &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

int
validation(self, ...)
        SV * self
    CODE:
        RETVAL = xmlDoValidityCheckingDefaultValue;
        if (items > 1) {
            xmlDoValidityCheckingDefaultValue = SvTRUE(ST(1)) ? 1 : 0;
        }
    OUTPUT:
        RETVAL

int
expand_entities(self, ...)
        SV * self
    CODE:
        RETVAL = xmlSubstituteEntitiesDefaultValue;
        if (items > 1) {
            xmlSubstituteEntitiesDefaultValue = SvTRUE(ST(1)) ? 1 : 0;
        }
    OUTPUT:
        RETVAL

int
keep_blanks(self, ...)
        SV * self
    CODE:
        RETVAL = xmlKeepBlanksDefaultValue;
        if (items > 1) {
            xmlKeepBlanksDefaultValue = SvTRUE(ST(1)) ? 1 : 0;
        }
    OUTPUT:
        RETVAL

int
pedantic_parser(self, ...)
        SV * self
    CODE:
        RETVAL = xmlPedanticParserDefaultValue;
        if (items > 1) {
            xmlPedanticParserDefaultValue = SvTRUE(ST(1)) ? 1 : 0;
        }
    OUTPUT:
        RETVAL

int
load_ext_dtd(self, ...)
        SV * self
    CODE:
        RETVAL = xmlLoadExtDtdDefaultValue;
        if (items > 1) {
            xmlLoadExtDtdDefaultValue = SvTRUE(ST(1)) ? 1 : 0;
        }
    OUTPUT:
        RETVAL

char *
get_last_error(CLASS)
        char * CLASS
    PREINIT:
        STRLEN len;
    CODE:
        RETVAL = SvPV(LibXML_error, len);
    OUTPUT:
        RETVAL

xmlDocPtr
_parse_string(self, string)
        SV * self
        SV * string
    PREINIT:
        xmlParserCtxtPtr ctxt;
        char * CLASS = "XML::LibXML::Document";
        STRLEN len;
        char * ptr;
        int well_formed;
        int ret;
    CODE:
        ptr = SvPV(string, len);
        ctxt = xmlCreateMemoryParserCtxt(ptr, len);
        ctxt->_private = (void*)self;
        
        ret = xmlParseDocument(ctxt);
        
        well_formed = ctxt->wellFormed;
        RETVAL = ctxt->myDoc;
        
        xmlFreeParserCtxt(ctxt);
        
        if (!well_formed) {
            xmlFreeDoc(RETVAL);
            croak(SvPV(LibXML_error, len));
        }
    OUTPUT:
        RETVAL

xmlDocPtr
_parse_fh(self, fh)
        SV * self
        SV * fh
    PREINIT:
        char * CLASS = "XML::LibXML::Document";
        STRLEN len;
    CODE:
        RETVAL = LibXML_parse_stream(self, fh);
        if (RETVAL == NULL) {
            croak(SvPV(LibXML_error, len));
        }
    OUTPUT:
        RETVAL
        
xmlDocPtr
_parse_file(self, filename)
        SV * self
        const char * filename
    PREINIT:
        xmlParserCtxtPtr ctxt;
        char * CLASS = "XML::LibXML::Document";
        int ret;
        STRLEN len;
    CODE:
        ctxt = xmlCreateFileParserCtxt(filename);
        ctxt->_private = (void*)self;
        
        xmlParseDocument(ctxt);
        RETVAL = ctxt->myDoc;
        ret = ctxt->wellFormed;
        
        xmlFreeParserCtxt(ctxt);
        
        if (!ret) {
            xmlFreeDoc(RETVAL);
            croak(SvPV(LibXML_error, len));
        }
    OUTPUT:
        RETVAL


MODULE = XML::LibXML         PACKAGE = XML::LibXML::Document

void
DESTROY(self)
        xmlDocPtr self
    CODE:
        if (self == NULL) {
           XSRETURN_UNDEF;
        }
             
        # warn("xmlFreeDoc(%d)\n", self);
        xmlFreeDoc(self);


SV *
toString(self, format=0)
        xmlDocPtr self
        int format
    PREINIT:
        xmlChar *result;
        int len;
    CODE:
        if ( format <= 0 ) {
            xmlDocDumpMemory(self, &result, &len);
        }
        else {
            xmlDocDumpFormatMemory( self, &result, &len, format ); 
        }
    	if (result == NULL) {
	        croak("Failed to convert doc to string");
    	} else {
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
        xmlDtdPtr dtd;
        SV * dtd_sv;
    CODE:
        if (items > 1) {
            dtd_sv = ST(1);
            if ( sv_isobject(dtd_sv) && (SvTYPE(SvRV(dtd_sv)) == SVt_PVMG) ) {
                dtd = (xmlDtdPtr)SvIV((SV*)SvRV( dtd_sv ));
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

void
process_xinclude(self)
        xmlDocPtr self
    CODE:
        xmlXIncludeProcess(self);

xmlDocPtr
new( CLASS, version="1.0", encoding=0 )
        char * CLASS
        char * version 
        char * encoding
    CODE:
        RETVAL = domCreateDocument( version, encoding ); 
    OUTPUT:
        RETVAL

xmlDocPtr
createDocument( CLASS, version="1.0", encoding=0 )
        char * CLASS
        char * version 
        char * encoding
    CODE:
        RETVAL = domCreateDocument( version, encoding ); 
    OUTPUT:
        RETVAL

ProxyObject *
createElement( dom, name )
        SV * dom
        char* name
    PREINIT:
        char * CLASS = "XML::LibXML::Element";
        xmlNodePtr newNode;
    CODE:
        newNode = xmlNewNode( 0 , name );
        newNode->doc = (xmlDocPtr)SvIV((SV*)SvRV(dom));
        RETVAL = make_proxy_node(newNode);
        RETVAL->extra = dom;
        SvREFCNT_inc(dom);
    OUTPUT:
        RETVAL

ProxyObject *
createTextNode( dom, content )
        SV * dom
        char * content
    PREINIT:
        char * CLASS = "XML::LibXML::Text";
        xmlNodePtr newNode;
    CODE:
        newNode = xmlNewDocText( (xmlDocPtr)SvIV((SV*)SvRV(dom)), content );
        RETVAL = make_proxy_node(newNode);
        RETVAL->extra = dom;
        SvREFCNT_inc(dom);
    OUTPUT:
        RETVAL

ProxyObject *
createComment( dom , content )
        SV * dom
        char * content
    PREINIT:
        char * CLASS = "XML::LibXML::Comment";
        xmlNodePtr newNode;
    CODE:
        newNode = xmlNewDocComment( (xmlDocPtr)SvIV((SV*)SvRV(dom)), content );
        RETVAL = make_proxy_node(newNode);
        RETVAL->extra = dom;
        SvREFCNT_inc(dom);
    OUTPUT:
        RETVAL

ProxyObject *
createCDATASection( dom, content )
        SV * dom
        char * content
    PREINIT:
        char * CLASS = "XML::LibXML::CDATASection";
        xmlNodePtr newNode;
    CODE:
        newNode = domCreateCDATASection( (xmlDocPtr)SvIV((SV*)SvRV(dom)), content );
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
    CODE:
        real_dom = (xmlDocPtr)SvIV((SV*)SvRV(dom));
        SvREFCNT_dec(proxy->extra);
        elem = (xmlNodePtr)proxy->object;
        domSetDocumentElement( real_dom, elem );
        proxy->extra = dom;
        SvREFCNT_inc(dom);

ProxyObject *
getDocumentElement( dom )
        SV * dom
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr elem;
        xmlDocPtr real_dom;
    CODE:
        real_dom = (xmlDocPtr)SvIV((SV*)SvRV(dom));
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

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Dtd

xmlDtdPtr
new(CLASS, external, system)
        char * CLASS
        char * external
        char * system
    CODE:
        RETVAL = xmlParseDTD((const xmlChar*)external, (const xmlChar*)system);
    OUTPUT:
        RETVAL

void
DESTROY( self )
        xmlDtdPtr self
    CODE:
        xmlFreeDtd(self);


MODULE = XML::LibXML         PACKAGE = XML::LibXML::Node

void
DESTROY( node )
        ProxyObject * node
    CODE:
        /**
         * this block should remove old (unbound) nodes from the system
         * but for some reason this condition is not valid ... :(
         **/
        if (node->extra != NULL) {
            SvREFCNT_dec(node->extra);
        }

        # warn( "Free node\n" );
        Safefree(node); 
    
    
	
int 
getType( node ) 
        xmlNodePtr node
    CODE:
        RETVAL = node->type;
    OUTPUT:
        RETVAL

void
unbindNode( elem )
        xmlNodePtr elem
    CODE:
        domUnbindNode( elem );

ProxyObject *
removeChild( paren, child ) 
        xmlNodePtr paren
        xmlNodePtr child
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr ret;
    CODE:
        ret = domRemoveNode( paren, child );
        RETVAL = NULL;
        if (ret != 0) {
            RETVAL = make_proxy_node(ret);
        }
    OUTPUT:
        RETVAL

ProxyObject *
replaceChild( paren, newChild, oldChild ) 
        xmlNodePtr paren
        xmlNodePtr newChild
        xmlNodePtr oldChild
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr ret;
    CODE:
        ret = domReplaceChild( paren, newChild, oldChild );
        RETVAL = NULL;
        if (ret != 0) {
            RETVAL = make_proxy_node(ret);
        }
    OUTPUT:
        RETVAL

void
appendChild( parent, child )
        xmlNodePtr parent
        xmlNodePtr child
    CODE:
        domAppendChild( parent, child );

ProxyObject *
cloneNode( self, deep ) 
        xmlNodePtr self
        int deep
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr ret;
    CODE:
        ret = xmlCopyNode( self, deep );
        RETVAL = NULL;
        if (ret != 0) {
            RETVAL = make_proxy_node(ret);
        }
    OUTPUT:
        RETVAL


ProxyObject *
getParentNode( self )
        xmlNodePtr self
    PREINIT:
        const char * CLASS = "XML::LibXML::Element";
        xmlNodePtr ret;
    CODE:
        ret = self->parent;
        RETVAL = NULL;
        if (ret != 0) {
            RETVAL = make_proxy_node(ret);
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
        xmlNodePtr elem
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr ret;
    CODE:
        ret = elem->next ;
        RETVAL = NULL;
        if ( ret ) {
            CLASS = domNodeTypeName( ret );
            RETVAL = make_proxy_node(ret);
        }	
    OUTPUT:
        RETVAL

ProxyObject *
getPreviousSibling( elem )
        xmlNodePtr elem
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr ret;
    CODE:
        ret = elem->prev;
        RETVAL = NULL;
        if ( ret ) {
            CLASS = domNodeTypeName( ret );
            RETVAL = make_proxy_node(ret);
        }
    OUTPUT:
        RETVAL

ProxyObject *
getFirstChild( elem )
        xmlNodePtr elem
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr ret;
    CODE:
        ret = elem->children;
        RETVAL = NULL;
        if ( ret ) {
            CLASS = domNodeTypeName( ret );
            RETVAL = make_proxy_node(ret);
        }
    OUTPUT:
        RETVAL


ProxyObject *
getLastChild( elem )
        xmlNodePtr elem
    PREINIT:
        const char * CLASS = "XML::LibXML::Node";
        xmlNodePtr ret;
    CODE:
        ret = elem->last;
        RETVAL = NULL;
        if ( ret ) {
            CLASS = domNodeTypeName( ret );
            RETVAL = make_proxy_node(ret);
        }
    OUTPUT:
        RETVAL


void
insertBefore( self, new, ref ) 
        xmlNodePtr self
        xmlNodePtr new
        xmlNodePtr ref
    CODE:
        domInsertBefore( self, new, ref );

void
insertAfter( self, new, ref )
        xmlNodePtr self
        xmlNodePtr new
        xmlNodePtr ref
    CODE:
        domInsertAfter( self, new, ref );

xmlDocPtr
getOwnerDocument( elem )
        xmlNodePtr elem
    PREINIT:
        const char * CLASS = "XML::LibXML::NoGCDocument";
    CODE:
        RETVAL = elem->doc;
    OUTPUT:
        RETVAL

void
setOwnerDocument( elem, doc )
        xmlNodePtr elem
        xmlDocPtr doc
    CODE:
        if ( doc ) {
            if ( elem->doc != doc ) {
                domUnbindNode( elem );
            }
            elem->doc = doc;
        }

SV*
getName( node )
        xmlNodePtr node
    PREINIT:
        const char * name;
    CODE:
        if( node != NULL ) {
            name =  node->name;
        }
        RETVAL = newSVpvn( (char *)name, xmlStrlen( name ) );
    OUTPUT:
        RETVAL

SV*
getData( node ) 
        xmlNodePtr node 
    PREINIT:
        const char * content;
    CODE:
        if( node != NULL ) {
            if ( node->type != XML_ATTRIBUTE_NODE ){
                content = node->content;
            }
            else if ( node->children != NULL ) {
                content = node->children->content;
            }
        }
        if ( content != 0 ){
            RETVAL = newSVpvn( (char *)content, xmlStrlen( content ) );
        }
        else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL


SV*
findnodes( node, xpath )
        xmlNodePtr node
        char * xpath 
    PREINIT:
        xmlNodeSetPtr nodelist;
        SV * element;
        int len;
    PPCODE:
        len = 0;
        nodelist = domXPathSelect( node, xpath );
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
                element = 0;
                tnode = nodelist->nodeTab[i];
                element = sv_newmortal();
                
                proxy = make_proxy_node(tnode);

                cls = domNodeTypeName( tnode );
                XPUSHs( sv_setref_pv( element, (char *)cls, (void*)proxy ) );
            }

            xmlXPathFreeNodeSet( nodelist );
        }
        XSRETURN(len);

SV*
getChildnodes( node )
        xmlNodePtr node
    PREINIT:
        xmlNodePtr cld;
        SV * element;
        int len;
        const char * cls = "XML::LibXML::Node";
        ProxyObject * proxy;
    PPCODE:
        len = 0;
	
        cld = node->children;
        while ( cld ) {	
            element = sv_newmortal();
            cls = domNodeTypeName( cld );
            proxy = make_proxy_node(cld);
            XPUSHs( sv_setref_pv( element, (char *)cls, (void*)proxy ) );
            cld = cld->next;
            len++;
        }
        XSRETURN(len);

SV*
toString( self )
        xmlNodePtr self
    PREINIT:
        xmlBufferPtr buffer;
    CODE:
        if ( self->type != XML_ATTRIBUTE_NODE ) {
            buffer = xmlBufferCreate();
            xmlNodeDump( buffer, self->doc, self, 0, 0 );
            if ( buffer->content != 0 ) {
                RETVAL = newSVpvn( buffer->content, buffer->use );
            }
            else {
                RETVAL = &PL_sv_undef;
            }
            xmlBufferFree( buffer );
        }
        else if ( self->children != NULL ) {
            RETVAL =  newSVpvn( self->children->content, 
                                xmlStrlen( self->children->content) );
        }
        else {
            RETVAL = &PL_sv_undef;
        }
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
        if ( newNode != 0 ) {
            newNode->next     = 0;
            newNode->prev     = 0;
            newNode->children = 0 ;
            newNode->last     = 0;
            newNode->doc      = 0;
            RETVAL = make_proxy_node(newNode);
        }
    OUTPUT:
        RETVAL


void
setAttribute( elem, name, value )
        xmlNodePtr elem	
        char * name
        char * value
    CODE:
        xmlSetProp( elem, name, value );

int 
hasAttribute( elem, name ) 
        xmlNodePtr elem
        char * name
    PREINIT:
        xmlAttrPtr att;
    CODE:
        /**
         * xmlHasProp() returns the attribute node, which is not exactly what 
         * we want as a boolean value 
         **/
        att = xmlHasProp( elem, name );
        RETVAL = att == NULL ? 0 : 1 ;
    OUTPUT:
        RETVAL

SV*
getAttribute( elem, name ) 
        xmlNodePtr elem
        char * name 
    PREINIT:
	    char * content;
    CODE:
        content = xmlGetProp( elem, name );
        if ( content != NULL ) {
            RETVAL  = newSVpvn( content, xmlStrlen( content ) );
        }
        else {
            RETVAL = NULL;
        }
    OUTPUT:
        RETVAL

void
removeAttribute( elem, name ) 	
        xmlNodePtr elem
        char * name
    CODE:
        xmlRemoveProp( xmlHasProp( elem, name ) );	

SV*
getElementsByTagName( elem, name )
        xmlNodePtr elem
        char * name 
    PREINIT:
        xmlNodeSetPtr nodelist;
        SV * element;
        int len;
    PPCODE:
        len = 0;
        nodelist = domGetElementsByTagName( elem , name );
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
                element = 0;
                tnode = nodelist->nodeTab[i];
                element = sv_newmortal();
                
                proxy = make_proxy_node(tnode);

                cls = domNodeTypeName( tnode );
                XPUSHs( sv_setref_pv( element, (char *)cls, (void*)proxy ) );
            }

            xmlXPathFreeNodeSet( nodelist );
        }
        XSRETURN(len);

void
appendWellBalancedChunk( self, chunk )
        xmlNodePtr self
        char * chunk
    PREINIT:
        xmlNodePtr rv;
    CODE:
        rv = domReadWellBalancedString( self->doc, chunk );
        if ( rv != NULL ) {
            xmlAddChildList( self , rv );
        }	

void 
appendTextNode( self, xmlString )
        xmlNodePtr self
        char * xmlString
    PREINIT: 
        xmlNodePtr tn;
    CODE:
        if ( self->doc != NULL && xmlString != NULL ) {
            if ( self->doc != NULL ) {
                tn = xmlNewDocText( self->doc, xmlString ); 
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
    CODE:
        xmlNewTextChild( self, NULL, childname, xmlString );

MODULE = XML::LibXML         PACKAGE = XML::LibXML::Text

void
setData( node, value )
        xmlNodePtr node
        char * value 
    CODE:
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
        RETVAL = make_proxy_node(newNode);
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
        RETVAL = make_proxy_node(newNode);
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
        newNode = xmlNewCDataBlock( 0 , content, xmlStrlen( content ) );
        RETVAL = make_proxy_node(newNode);
    OUTPUT:
        RETVAL

