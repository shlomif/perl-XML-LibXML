/**
 * perl-libxml-sax.c
 * $Id$
 */

#ifdef __cplusplus
extern "C" {
#endif
#define PERL_NO_GET_CONTEXT     /* we want efficiency */


#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include <stdlib.h>
#include <libxml/xmlmemory.h>
#include <libxml/parser.h>
#include <libxml/parserInternals.h>
#include <libxml/tree.h>
#include <libxml/entities.h>
#include <libxml/xmlerror.h>

#ifdef __cplusplus
}
#endif

#define NSDELIM ':'
#define NSDEFAULTURI "http://www.w3.org/XML/1998/namespace"

typedef struct {
    SV * parser;
    xmlNodePtr ns_stack;
    xmlSAXLocator * locator;
    xmlDocPtr ns_stack_root;
    SV * handler;
} PmmSAXVector;

typedef PmmSAXVector* PmmSAXVectorPtr;

static U32 PrefixHash; /* pre-computed */
static U32 NsURIHash;
static U32 NameHash;
static U32 LocalNameHash;
static U32 AttributesHash;
static U32 ValueHash;
static U32 DataHash;
static U32 TargetHash;
static U32 VersionHash;
static U32 EncodingHash;

/* helper function C2Sv is ment to work faster than the perl-libxml-mm
   version. this shortcut is usefull, because SAX handles only UTF8
   strings, so there is no conversion logic required.
*/
SV*
_C2Sv( const xmlChar *string, const xmlChar *dummy )
{

    dTHX;
    SV *retval = &PL_sv_undef;
    STRLEN len;

    if ( string != NULL ) {
        len = xmlStrlen( string );
        retval = newSVpvn( (const char *)string, len );
#ifdef HAVE_UTF8
        SvUTF8_on( retval );
#endif

    }
    return retval;
}

void
PmmSAXInitialize()
{
    PERL_HASH(PrefixHash,     "Prefix",        6);
    PERL_HASH(NsURIHash,      "NamespaceURI", 12);
    PERL_HASH(NameHash,       "Name",          4);
    PERL_HASH(LocalNameHash,  "LocalName",     9);
    PERL_HASH(AttributesHash, "Attributes",   10);
    PERL_HASH(ValueHash,      "Value",         5);
    PERL_HASH(DataHash,       "Data",          4);
    PERL_HASH(TargetHash,     "Target",        6);
    PERL_HASH(VersionHash,    "Version",       7);
    PERL_HASH(EncodingHash,   "Encoding",      8);
}

void
PmmSAXInitContext( xmlParserCtxtPtr ctxt, SV * parser )
{
    xmlNodePtr ns_stack = NULL;
    PmmSAXVectorPtr vec = NULL;
    SV ** th;
    dTHX;

    vec = (PmmSAXVector*) xmlMalloc( sizeof(PmmSAXVector) );
    vec->ns_stack_root = xmlNewDoc(NULL);
    vec->ns_stack      = xmlNewDocNode(vec->ns_stack_root,
                                       NULL,
                                       "stack",
                                       NULL );

    xmlAddChild((xmlNodePtr)vec->ns_stack_root, vec->ns_stack);

    vec->locator = NULL;

    SvREFCNT_inc( parser );
    vec->parser  = parser;
    th = hv_fetch( (HV*)SvRV(parser), "HANDLER", 7, 0 );
    if ( th != NULL && SvTRUE(*th) ) {
        vec->handler = newSVsv(*th)  ;
    }
    else {
        vec->handler = NULL  ;
    }

    ctxt->_private = (void*)vec;
}

void 
PmmSAXCloseContext( xmlParserCtxtPtr ctxt )
{
    PmmSAXVector * vec = (PmmSAXVectorPtr) ctxt->_private;
    dTHX;
    
    if ( vec->handler ) {
        SvREFCNT_dec( vec->handler );
        vec->handler = NULL;
    }
    SvREFCNT_dec( vec->parser );

    xmlFreeDoc( vec->ns_stack_root );
    xmlFree( vec );
}


xmlNsPtr
PmmGetNsMapping( xmlNodePtr ns_stack, const xmlChar * prefix )
{
    if ( ns_stack != NULL ) {
        return xmlSearchNs( ns_stack->doc, ns_stack, prefix );
    }
    
    return NULL;
}


void
PSaxStartPrefix( PmmSAXVectorPtr sax, const xmlChar * prefix,
                 const xmlChar * uri, SV * handler )
{
    dTHX;
    HV * param;
    SV * rv;

    dSP;

    ENTER;
    SAVETMPS;

    param = newHV();
    hv_store(param, "NamespaceURI", 12,
             _C2Sv(uri, NULL), NsURIHash);

    if ( prefix != NULL ) {
        hv_store(param, "Prefix", 6,
                 _C2Sv(prefix, NULL), PrefixHash);
    }
    else {
/*         warn("null prefix!\n" ); */
        hv_store(param, "Prefix", 6,
                 _C2Sv("", NULL), PrefixHash);
    }

    PUSHMARK(SP) ;
    XPUSHs(handler);


    rv = newRV_noinc((SV*)param);

    XPUSHs(rv);
    PUTBACK;

    perl_call_method( "start_prefix_mapping", 0 );
    sv_2mortal(rv);
    FREETMPS ;
    LEAVE ;
}

void
PSaxEndPrefix( PmmSAXVectorPtr sax, const xmlChar * prefix,
               const xmlChar * uri, SV * handler )
{
    dTHX;
    HV * param;
    SV * rv;

    dSP;

    ENTER;
    SAVETMPS;
    param = newHV();
    hv_store(param, "NamespaceURI", 12,
             _C2Sv(uri, NULL), NsURIHash);

    if ( prefix != NULL ) {
        hv_store(param, "Prefix", 6,
                 _C2Sv(prefix, NULL), PrefixHash);
    }
    else {
/*         warn("null prefix!\n" ); */
        hv_store(param, "Prefix", 6,
                 _C2Sv("", NULL), PrefixHash);
    }

    PUSHMARK(SP) ;
    XPUSHs(handler);


    rv = newRV_noinc((SV*)param);

    XPUSHs(rv);
    PUTBACK;

    perl_call_method( "end_prefix_mapping", 0 );

    sv_2mortal(rv);

    FREETMPS ;
    LEAVE ;
}

void 
PmmExtendNsStack( PmmSAXVectorPtr sax , const xmlChar * name) {
    xmlNodePtr newNS = xmlNewDocNode( sax->ns_stack_root, NULL, name, NULL );
    xmlAddChild(sax->ns_stack, newNS);
    sax->ns_stack = newNS;
}

void
PmmNarrowNsStack( PmmSAXVectorPtr sax, SV *handler )
{
    xmlNodePtr parent = sax->ns_stack->parent;
    xmlNsPtr list = sax->ns_stack->nsDef;
    while ( list ) {
        xmlNsPtr tmp = list;
        if ( !xmlStrEqual(list->prefix, "xml") ) {
            PSaxEndPrefix( sax, list->prefix, list->href, handler );
        }
        list = list->next;        
    }
    xmlUnlinkNode(sax->ns_stack);
    xmlFreeNode(sax->ns_stack);
    sax->ns_stack = parent;
}

void
PmmAddNamespace( PmmSAXVectorPtr sax, const xmlChar * name,
                 const xmlChar * href, SV *handler)
{
    xmlNsPtr ns         = NULL;
    xmlChar * nodename  = NULL;
    xmlChar * prefix    = NULL;
    xmlChar * localname = NULL;


    if ( sax->ns_stack == NULL ) {
        return;
    }

    localname = xmlSplitQName( NULL, sax->ns_stack->name, &prefix );

    ns = xmlNewNs( sax->ns_stack, href, name );         
    PSaxStartPrefix( sax, name, href, handler );

    if ( name != NULL ) {
        if ( sax->ns_stack->ns == NULL
             && xmlStrEqual( prefix , name ) ) {
            sax->ns_stack->ns = ns;
            xmlFree( (xmlChar*) sax->ns_stack->name );
            sax->ns_stack->name = (const xmlChar*) xmlStrdup( localname );
        }
    }
    else if ( prefix == NULL && sax->ns_stack->ns == NULL) {
        sax->ns_stack->ns = ns;
    }
    xmlFree( prefix );
    xmlFree( localname );
}

HV *
PmmGenElementSV( pTHX_ PmmSAXVectorPtr sax, const xmlChar * name )
{
    HV * retval = newHV();
    SV * tmp;

    xmlNsPtr ns = NULL;
    if ( name != NULL && xmlStrlen( name )  ) {
        xmlChar *localname = NULL, *prefix = NULL;
        hv_store(retval, "Name", 4,
                 _C2Sv(name, NULL), NameHash);

        if ( sax->ns_stack->ns != NULL ) {  
            ns = sax->ns_stack->ns;
/*             warn("found ns") ; */
        }

        tmp = _C2Sv("",NULL);
        
        if ( ns != NULL ) {
/*             warn(" namespaced element\n" ); */

            hv_store(retval, "NamespaceURI", 12,
                     _C2Sv(ns->href, NULL), NsURIHash);
            if ( ns->prefix ) {
                hv_store(retval, "Prefix", 6,
                         _C2Sv(ns->prefix, NULL), PrefixHash);
            }
            else {
                hv_store(retval, "Prefix", 6,
                         tmp, PrefixHash);
            }

            hv_store(retval, "LocalName", 9,
                     _C2Sv(sax->ns_stack->name, NULL), LocalNameHash);
        }
        else {
            hv_store(retval, "NamespaceURI", 12,
                     tmp, NsURIHash);
            hv_store(retval, "Prefix", 6,
                     SvREFCNT_inc(tmp), PrefixHash);
            hv_store(retval, "LocalName", 9,
                     _C2Sv(name, NULL), LocalNameHash);
        }
    }

    return retval;
}

xmlChar *
PmmGenNsName( const xmlChar * name, const xmlChar * nsURI )
{
    int namelen = 0;
    int urilen = 0;
    xmlChar * retval = NULL;

    if ( name == NULL ) {
        return NULL;
    }
    namelen = xmlStrlen( name );
    if ( nsURI != NULL ) {
        urilen = xmlStrlen( nsURI );
    }

    retval =xmlStrncat( retval, "{",1 );
    if ( nsURI != NULL ) {
        retval =xmlStrncat( retval, nsURI, urilen );
    } 
    retval = xmlStrncat( retval, "}",1 );
    retval = xmlStrncat( retval, name, namelen );
    return retval;
}

HV *
PmmGenAttributeHashSV( pTHX_ PmmSAXVectorPtr sax,
                       const xmlChar **attr, SV * handler )
{
    HV * retval     = NULL;
    HV * atV        = NULL;
    xmlNsPtr ns     = NULL;

    U32 atnameHash = 0;
    int len = 0;

    const xmlChar * nsURI = NULL;
    const xmlChar **ta    = attr;
    const xmlChar * name  = NULL;
    const xmlChar * value = NULL;

    xmlChar * keyname     = NULL;
    xmlChar * localname   = NULL;
    xmlChar * prefix      = NULL;

    retval = newHV();

    if ( ta != NULL ) {

        while ( *ta != NULL ) {
            atV = newHV();
            name = *ta;  ta++;
            value = *ta; ta++;

            if ( name != NULL && xmlStrlen( name ) ) {

                hv_store(atV, "Name", 4,
                         _C2Sv(name, NULL), NameHash);
                if ( value != NULL ) {
                    hv_store(atV, "Value", 5,
                             _C2Sv(value, NULL), ValueHash);
                }

                if ( xmlStrEqual( "xmlns", name ) ) {
                    /* a default namespace */
                    PmmAddNamespace( sax, NULL, value, handler);  
                    nsURI = "http://www.w3.org/2000/xmlns/";

                    hv_store(atV, "Prefix", 6,
                             _C2Sv(name, NULL), PrefixHash);
                    hv_store(atV, "LocalName", 9,
                             _C2Sv("",NULL), LocalNameHash);
                    hv_store(atV, "NamespaceURI", 12,
                             _C2Sv("http://www.w3.org/2000/xmlns/",NULL),
                             NsURIHash);
                    
                }
                else if (xmlStrncmp("xmlns:", name, 6 ) == 0 ) {
                    localname = xmlSplitQName(NULL, name, &prefix);                        
                    PmmAddNamespace( sax,
                                     localname,
                                     value,
                                     handler);
                  
                    nsURI = "http://www.w3.org/2000/xmlns/";
                    
                    hv_store(atV, "Prefix", 6,
                             _C2Sv(prefix, NULL), PrefixHash);
                    hv_store(atV, "LocalName", 9,
                             _C2Sv(localname,NULL), LocalNameHash);
                    hv_store(atV, "NamespaceURI", 12,
                             _C2Sv(nsURI,NULL),
                             NsURIHash);
                    xmlFree( prefix );
                }
                else if ( ns = PmmGetNsMapping( sax->ns_stack, prefix ) ) {
                    localname = xmlSplitQName(NULL, name, &prefix);        
                        
                    hv_store(atV, "NamespaceURI", 12,
                             _C2Sv(ns->href, NULL), NsURIHash);
                    hv_store(atV, "Prefix", 6,
                             _C2Sv(ns->prefix, NULL), PrefixHash);
                    hv_store(atV, "LocalName", 9,
                             _C2Sv(localname, NULL), LocalNameHash);
                    xmlFree( prefix );
                }
                else {
                    hv_store(atV, "NamespaceURI", 12,
                             _C2Sv("",NULL), NsURIHash);
                    hv_store(atV, "Prefix", 6,
                             _C2Sv("", NULL), PrefixHash);
                    hv_store(atV, "LocalName", 9,
                             _C2Sv(name, NULL), LocalNameHash);
                }

                keyname = PmmGenNsName( localname!= NULL ? localname: name,
                                        nsURI );

                len = xmlStrlen( keyname );
                PERL_HASH( atnameHash, keyname, len );
                hv_store(retval,
                         keyname,
                         len,
                         newRV_noinc((SV*)atV),
                         atnameHash );

                xmlFree( keyname );
                xmlFree(localname);
            }            
        }
    }

    return retval;
}

HV * 
PmmGenCharDataSV( pTHX_ PmmSAXVectorPtr sax, const xmlChar * data )
{
    HV * retval = newHV();

    if ( data != NULL && xmlStrlen( data ) ) {
        hv_store(retval, "Data", 4,
                 _C2Sv(data, NULL), DataHash);
    }

    return retval;
}

HV * 
PmmGenPISV( pTHX_ PmmSAXVectorPtr sax,
            const xmlChar * target,
            const xmlChar * data )
{
    HV * retval = newHV();

    if ( target != NULL && xmlStrlen( target ) ) {
        hv_store(retval, "Target", 6,
                 _C2Sv(target, NULL), TargetHash);

        if ( data != NULL && xmlStrlen( data ) ) {
            hv_store(retval, "Data", 4,
                     _C2Sv(data, NULL), DataHash);
        }
        else {
            hv_store(retval, "Data", 4,
                     _C2Sv("", NULL), DataHash);
        }
    }

    return retval;
}

int
PSaxStartDocument(void * ctx)
{
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax   = (PmmSAXVectorPtr)ctxt->_private;
    int count             = 0;
    dTHX;
    HV* real_obj          = (HV *)SvRV(sax->parser);
    HV* empty             = newHV();
    SV * handler         = sax->handler;

    SV * rv;

    if ( handler != NULL ) {
        dSP;
        
        ENTER;
        SAVETMPS;
        
        PUSHMARK(SP) ;
        XPUSHs(handler);
        XPUSHs(sv_2mortal(newRV_inc((SV*)empty)));
        PUTBACK;
        
        count = perl_call_method( "start_document", 0 );
        
        SPAGAIN;
        
        PUSHMARK(SP) ;

    
        XPUSHs(handler);


        if ( ctxt->version != NULL ) {
            hv_store(empty, "Version", 7,
                     _C2Sv(ctxt->version, NULL), VersionHash);
        }
        else {
            hv_store(empty, "Version", 7,
                     _C2Sv("1.0", NULL), VersionHash);
        }
        
        if ( ctxt->encoding != NULL ) {
            hv_store(empty, "Encoding", 8,
                     _C2Sv(ctxt->encoding, NULL), EncodingHash);
        }
        rv = newRV_noinc((SV*)empty);
        XPUSHs( rv);

        PUTBACK;
        
        count = perl_call_method( "xml_decl", 0 );
        sv_2mortal(rv);

        FREETMPS ;
        LEAVE ;
    }

    return 1;
}

int
PSaxEndDocument(void * ctx)
{
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr  sax  = (PmmSAXVectorPtr)ctxt->_private;
    int count             = 0;

    dTHX;
    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(sax->parser);
    PUTBACK;

    count = perl_call_pv( "XML::LibXML::_SAXParser::end_document", 0 );

    FREETMPS ;
    LEAVE ;

    return 1;
}

int
PSaxStartElement(void *ctx, const xmlChar * name, const xmlChar** attr)
{
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr  sax  = (PmmSAXVectorPtr)ctxt->_private;
    int count             = 0;
    dTHX;
    HV * attrhash         = NULL;
    HV * real_obj         = (HV *)SvRV(sax->parser);
    HV * element          = NULL;
    SV * handler         = sax->handler;
    SV * rv;
    SV * arv;

    dSP;
    
    ENTER;
    SAVETMPS;

    PmmExtendNsStack(sax, name);

    attrhash = PmmGenAttributeHashSV(aTHX_ sax, attr, handler );
    element  = PmmGenElementSV(aTHX_ sax, name);

    arv = newRV_noinc((SV*)attrhash);
    hv_store( element,
              "Attributes",
              10,
              arv,
              AttributesHash );
    
    PUSHMARK(SP) ;

    XPUSHs(handler);
    rv = newRV_noinc((SV*)element);
    XPUSHs(rv);
    PUTBACK;

    count = perl_call_method( "start_element", 0 );
    
    sv_2mortal(rv) ;

    FREETMPS ;
    LEAVE ;


    return 1;
}

int
PSaxEndElement(void *ctx, const xmlChar * name) {
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr  sax  = (PmmSAXVectorPtr)ctxt->_private;
    dTHX;
    int count;
/*     HV* real_obj          = (HV *)SvRV(sax->parser); */
    SV * handler         = sax->handler;
    SV * rv;
    HV * element;

    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(handler);

    element = PmmGenElementSV(aTHX_ sax, name);
    rv = newRV_noinc((SV*)element);

    XPUSHs(rv);
    PUTBACK;

    count = perl_call_method( "end_element", 0 );

    sv_2mortal(rv);

    FREETMPS ;
    LEAVE ;

    PmmNarrowNsStack(sax, handler);

    return 1;
}

int
PSaxCharacters(void *ctx, const xmlChar * ch, int len) {
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;
    int count = 0;
    dTHX;
    HV* real_obj = (HV *)SvRV(sax->parser);
    HV* element;
    SV * handler = sax->handler;
    
    SV * rv = NULL;

    if ( ch != NULL && handler != NULL ) {
        xmlChar * data = xmlStrndup( ch, len );

        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;
        XPUSHs(handler);
        element = PmmGenCharDataSV(aTHX_ sax,data);
        rv = newRV_noinc((SV*)element);
        XPUSHs(rv);
        PUTBACK;

        count = perl_call_method( "characters", 0 );

        sv_2mortal(rv);

        FREETMPS ;
        LEAVE ;

        xmlFree( data );
    }

    return 1;
}

int
PSaxComment(void *ctx, const xmlChar * ch) {
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;
    int count = 0;
    dTHX;
    HV* real_obj = (HV *)SvRV(sax->parser);
    HV* element;
    SV * handler = sax->handler;
    
    SV * rv = NULL;

    if ( ch != NULL && handler != NULL ) {
        xmlChar * data = xmlStrdup( ch );

        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;
        XPUSHs(handler);
        element = PmmGenCharDataSV(aTHX_ sax,data);
        rv = newRV_noinc((SV*)element);
        XPUSHs(rv);
        PUTBACK;

        count = perl_call_method( "comment", 0 );

        sv_2mortal(rv);

        FREETMPS ;
        LEAVE ;

        xmlFree( data );
    }

    return 1;
}

int
PSaxCDATABlock(void *ctx, const xmlChar * ch, int len) {
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;
    int count = 0;
    dTHX;
    HV* real_obj = (HV *)SvRV(sax->parser);
    HV* element;
    SV * handler = sax->handler;
    
    SV * rv = NULL;

    if ( ch != NULL && handler != NULL ) {
        xmlChar * data = xmlStrndup( ch, len );

        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;
        XPUSHs(handler);
        element = PmmGenCharDataSV(aTHX_ sax,data);
        rv = newRV_noinc((SV*)element);
        XPUSHs(rv);
        PUTBACK;

        count = perl_call_pv( "XML::LibXML::_SAXParser::cdata_block", 0 );

        sv_2mortal(rv);

        FREETMPS ;
        LEAVE ;

        xmlFree( data );
    }

    return 1;

}

int
PSaxProcessingInstruction( void * ctx, const xmlChar * target, const xmlChar * data )
{
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax   = (PmmSAXVectorPtr)ctxt->_private;
    int count             = 0;
    dTHX;
    HV* real_obj          = (HV *)SvRV(sax->parser);
    HV* empty             = newHV();
    SV * handler         = sax->handler;

    SV * element;
    SV * rv = NULL;

    if ( handler != NULL ) {
        dSP;
    
        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;
        XPUSHs(handler);
        element = PmmGenPISV(aTHX_ sax, target, data);
        rv = newRV_noinc((SV*)element);
        XPUSHs(rv);

        PUTBACK;

        count = perl_call_method( "processing_instruction", 0 );

        sv_2mortal(rv);

        FREETMPS ;
        LEAVE ;
    }
    return 1;
}

int
PmmSaxWarning(void * ctx, const char * msg, ...)
{
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;

    va_list args;
    SV * svMessage;

    dTHX;
    dSP;
    svMessage = NEWSV(0,512);

    va_start(args, msg);
    sv_vsetpvfn(svMessage, msg, xmlStrlen(msg), &args, NULL, 0, NULL);
    va_end(args);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(sax->parser);

    XPUSHs(sv_2mortal(svMessage));
    XPUSHs(sv_2mortal(newSViv(ctxt->input->line)));
    XPUSHs(sv_2mortal(newSViv(ctxt->input->col)));

    PUTBACK;

    perl_call_pv( "XML::LibXML::_SAXParser::warning", 0 );
    
    FREETMPS ;
    LEAVE ;
    SvREFCNT_dec(svMessage);
    return 1;
}


int
PmmSaxError(void * ctx, const char * msg, ...)
{
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;

    va_list args;
    SV * svMessage;
 
    dTHX;
    dSP;

    svMessage = NEWSV(0,512);

    va_start(args, msg);
    sv_vsetpvfn(svMessage, msg, xmlStrlen(msg), &args, NULL, 0, NULL);
    va_end(args);


    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(sax->parser);

    XPUSHs(sv_2mortal(svMessage));
    XPUSHs(sv_2mortal(newSViv(ctxt->input->line)));
    XPUSHs(sv_2mortal(newSViv(ctxt->input->col)));
    PUTBACK;
    perl_call_pv( "XML::LibXML::_SAXParser::error", 0 );
    
    FREETMPS ;
    LEAVE ;
    SvREFCNT_dec(svMessage);
    return 1;
}


int
PmmSaxFatalError(void * ctx, const char * msg, ...)
{
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;

    va_list args;
    SV * svMessage;
 
    dTHX;
    dSP;

    svMessage = NEWSV(0,512);

    va_start(args, msg);
    sv_vsetpvfn(svMessage, msg, xmlStrlen(msg), &args, NULL, 0, NULL);
    va_end(args);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(sax->parser);

    XPUSHs(sv_2mortal(svMessage));
    XPUSHs(sv_2mortal(newSViv(ctxt->input->line)));
    XPUSHs(sv_2mortal(newSViv(ctxt->input->col)));
    PUTBACK;
    perl_call_pv( "XML::LibXML::_SAXParser::fatal_error", 0 );
    
    FREETMPS ;
    LEAVE ;
    SvREFCNT_dec(svMessage);
    return 1;
}

/* NOTE:
 * end document is not handled by the parser itself! use 
 * XML::LibXML::SAX instead!
 */
xmlSAXHandlerPtr
PSaxGetHandler()
{
    xmlSAXHandlerPtr retval = (xmlSAXHandlerPtr)xmlMalloc(sizeof(xmlSAXHandler));
    memset(retval, 0, sizeof(xmlSAXHandler));

    retval->startDocument = (startDocumentSAXFunc)&PSaxStartDocument;

    /* libxml2 will not handle perls returnvalue correctly, so we have 
     * to end the document ourselfes
     */
    retval->endDocument   = NULL; /* (endDocumentSAXFunc)&PSaxEndDocument; */

    retval->startElement  = (startElementSAXFunc)&PSaxStartElement;
    retval->endElement    = (endElementSAXFunc)&PSaxEndElement;

    retval->characters    = (charactersSAXFunc)&PSaxCharacters;
    retval->ignorableWhitespace = (ignorableWhitespaceSAXFunc)&PSaxCharacters;

    retval->comment       = (commentSAXFunc)&PSaxComment;
    retval->cdataBlock    = (cdataBlockSAXFunc)&PSaxCDATABlock;

    retval->processingInstruction = (processingInstructionSAXFunc)&PSaxProcessingInstruction;

    /* warning functions should be internal */
    retval->warning    = (warningSAXFunc)&PmmSaxWarning;
    retval->error      = (errorSAXFunc)&PmmSaxError;
    retval->fatalError = (fatalErrorSAXFunc)&PmmSaxFatalError;

    return retval;
}

