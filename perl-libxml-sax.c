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
#include <libxml/tree.h>
#include <libxml/entities.h>
#include <libxml/xmlerror.h>

#include "perl-libxml-mm.h"

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

void
PmmSAXInitialize() {
    PERL_HASH(PrefixHash, "Prefix", 6);
    PERL_HASH(NsURIHash, "NamespaceURI", 12);
    PERL_HASH(NameHash, "Name", 4);
    PERL_HASH(LocalNameHash, "LocalName", 9);
    PERL_HASH(AttributesHash, "Attributes", 10);
    PERL_HASH(ValueHash, "Value", 5);
    PERL_HASH(DataHash, "Data", 4);
    PERL_HASH(TargetHash, "Target", 6);
}

void
PmmSAXInitContext( xmlParserCtxtPtr ctxt, SV * parser ) {
    xmlNodePtr ns_stack = NULL;
    PmmSAXVectorPtr vec = NULL;
    dTHX;

    vec = (PmmSAXVector*) xmlMalloc( sizeof(PmmSAXVector) );
    vec->ns_stack_root = xmlNewDoc(NULL);
    vec->ns_stack = xmlNewDocNode(vec->ns_stack_root,NULL , "stack", NULL );
    xmlAddChild((xmlNodePtr)vec->ns_stack_root, vec->ns_stack);
    vec->locator = NULL;
    SvREFCNT_inc( parser );
    vec->parser = parser;
    ctxt->_private = (void*)vec;
}

void 
PmmSAXCloseContext( xmlParserCtxtPtr ctxt ) {
    PmmSAXVector * vec = (PmmSAXVectorPtr) ctxt->_private;
    dTHX;

    vec = (PmmSAXVector*) ctxt->_private;
    SvREFCNT_dec( vec->parser );
    xmlFreeDoc( vec->ns_stack_root );
    xmlFree( vec );
}


xmlNsPtr
PmmGetNsMapping( xmlNodePtr ns_stack, const xmlChar * prefix ) {
    xmlNsPtr ret = NULL;
    if ( ns_stack != NULL ) {
        if ( prefix != NULL) {
            ret = xmlSearchNs( ns_stack->doc, ns_stack, prefix );
        }
        else {
            ret = xmlSearchNs( ns_stack->doc, ns_stack, NULL );
        }

    }
    
    return ret;
}


void
PSaxStartPrefix( PmmSAXVectorPtr sax, const xmlChar * prefix, const xmlChar * uri )
{
    dTHX;
    dSP;
    
    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(sax->parser);
    if ( prefix != NULL ) {
        XPUSHs( sv_2mortal( C2Sv(prefix, NULL) ) );
    }
    else {
        XPUSHs( sv_2mortal( C2Sv("", NULL) ) );
    }
    XPUSHs( sv_2mortal( C2Sv(uri, NULL) ) );
    PUTBACK;

    perl_call_pv( "XML::LibXML::_SAXParser::start_prefix_mapping", 0 );

    FREETMPS ;
    LEAVE ;
}

void
PSaxEndPrefix( PmmSAXVectorPtr sax, const xmlChar * prefix, const xmlChar * uri )
{
    dTHX;
    dSP;
    
    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(sax->parser);
    if ( prefix != NULL ) {
        XPUSHs( sv_2mortal( C2Sv(prefix, NULL) ) );
    }
    else {
        XPUSHs( sv_2mortal( C2Sv("", NULL) ) );
    }
    XPUSHs( sv_2mortal( C2Sv(uri, NULL) ) );
    PUTBACK;

    perl_call_pv( "XML::LibXML::_SAXParser::end_prefix_mapping", 0 );

    FREETMPS ;
    LEAVE ;
}

void 
PmmExtendNsStack( PmmSAXVectorPtr sax ) {
    xmlNodePtr newNS = xmlNewDocNode( sax->ns_stack_root, NULL, "stack", NULL );
    xmlAddChild(sax->ns_stack, newNS);
    sax->ns_stack = newNS;
}

void
PmmNarrowNsStack( PmmSAXVectorPtr sax ) {
    xmlNodePtr parent = sax->ns_stack->parent;
    xmlNsPtr list = sax->ns_stack->nsDef;
    while ( list ) {
        if ( !xmlStrEqual(list->prefix, "xml") ) {
            PSaxEndPrefix( sax, list->prefix, list->href );
        }
        list = list->next;
    }
    xmlUnlinkNode(sax->ns_stack);
    sax->ns_stack = parent;
}


const xmlChar *
PmmDetectNamespace( const xmlChar * name ) {
    const xmlChar *pos = xmlStrchr( name, (xmlChar)NSDELIM );
    if ( pos != NULL ) {
        return pos;
    }
    return NULL;    
}

const xmlChar *
PmmDetectNamespaceDecl( const xmlChar * name ) {
    const xmlChar *pos = xmlStrchr( name, (xmlChar)NSDELIM );
    xmlChar *decl= NULL;
    int len = 0;

    if ( xmlStrcmp( "xmlns", name ) == 0 ) {
        return name;
    }

    if ( pos == NULL ) {
        return NULL;
    }

    len = pos - name;
    decl = xmlStrndup( name, len );
    
    if ( xmlStrcmp( "xmlns", decl ) != 0 ) {
        pos= NULL;
    }

    xmlFree( decl );

    return pos;
}

void
PmmAddNamespace( PmmSAXVectorPtr sax, const xmlChar * name, const xmlChar * href) {
    if ( sax->ns_stack != NULL ) {
        xmlNsPtr ns = NULL;
        const xmlChar *pos = xmlStrchr( name, NSDELIM );
        xmlChar *decl= NULL;
        if ( pos != NULL ) {
            pos++;
            decl = xmlStrdup( pos );
            if ( decl != NULL && xmlStrlen( decl ) ) {
                ns = xmlNewNs( sax->ns_stack, href,decl );
            }
         
            PSaxStartPrefix( sax, decl, href );
            xmlFree( decl );
        }
        else {
            ns = xmlNewNs( sax->ns_stack, href, NULL );
            PSaxStartPrefix( sax, NULL, href );
        }
    }
}

HV *
PmmGenElementSV( pTHX_ PmmSAXVectorPtr sax, const xmlChar * name ) {
    HV * retval = newHV();
    SV *empty_sv = sv_2mortal(C2Sv("", NULL));

    xmlNsPtr ns = NULL;
    if ( name != NULL && xmlStrlen( name )  ) {
        const xmlChar * pos = PmmDetectNamespace( name );

        hv_store(retval, "Name", 4,
                 C2Sv(name, NULL), NameHash);

        if ( pos != NULL ) {
            xmlChar * localname = NULL;
            xmlChar * prefix = NULL;
            prefix = xmlStrndup( name, pos - name );
            /* pos++; skip the colon */
            localname = xmlStrdup(++pos);
            ns = PmmGetNsMapping( sax->ns_stack, prefix );

            hv_store(retval, "Prefix", 6,
                     C2Sv(prefix, NULL), PrefixHash);

            if ( ns != NULL ) {
                hv_store(retval, "NamespaceURI", 12,
                         C2Sv(ns->href, NULL), NsURIHash);
            } 
            else {
                hv_store(retval, "NamespaceURI", 12,
                         SvREFCNT_inc(empty_sv), NsURIHash);
            }

            hv_store(retval, "LocalName", 9,
                     C2Sv(localname, NULL), LocalNameHash);
            
            xmlFree(localname);
            xmlFree(prefix);
        }
        else {
            hv_store(retval, "Prefix", 6,
                     SvREFCNT_inc(empty_sv), PrefixHash);
            hv_store(retval, "NamespaceURI", 12,
                     SvREFCNT_inc(empty_sv), NsURIHash);
            hv_store(retval, "LocalName", 9,
                     C2Sv(name, NULL), LocalNameHash);
        }
                
    }
    return retval;
}

xmlChar *
PmmGenNsName( const xmlChar * name, xmlChar * nsURI ) {
    int namelen = 0;
    int urilen = 0;
    xmlChar * retval = NULL;
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
PmmGenAttributeHashSV( pTHX_ PmmSAXVectorPtr sax, const xmlChar **attr ) {
    HV * retval = newHV();
    HV * atV = NULL;
    SV *empty_sv = sv_2mortal(C2Sv("", NULL));
    xmlChar * nsURI = NULL;

    U32 atnameHash;
    int len = 0;
    const xmlChar **ta = attr;
    const xmlChar * name = NULL;
    const xmlChar * value = NULL;
    xmlChar * keyname;

    if ( attr != NULL ) {
        while ( *ta != NULL ) {
            name = *ta; ta++;
            value = *ta; ta++;
            if (PmmDetectNamespaceDecl(name)) {
                PmmAddNamespace(sax, name, value);  
            }
        }

        ta = attr;

        while ( *ta != NULL ) {
            xmlChar * localname = NULL;
            atV = newHV();
            name = *ta; ta++;
            value = *ta; ta++;
            if (PmmDetectNamespaceDecl(name)) {
                continue;
            }
            if ( name != NULL && xmlStrlen( name ) ) {
                const xmlChar * pos = PmmDetectNamespace( name );

                hv_store(atV, "Name", 4,
                         C2Sv(name, NULL), NameHash);
                hv_store(atV, "Value", 5,
                         C2Sv(value, NULL), ValueHash);
                
                if ( pos != NULL ) {
                    xmlNsPtr ns = NULL;
                    xmlChar * prefix = NULL;
            
                    prefix = xmlStrndup( name, pos - name );
                    /* pos++; skip the colon */
                    localname = xmlStrdup(++pos);
                    
                    ns = PmmGetNsMapping( sax->ns_stack, prefix );
            
                    hv_store(atV, "Prefix", 6,
                             C2Sv(prefix, NULL), PrefixHash);

                    if ( ns != NULL ) {
                        nsURI = xmlStrdup( ns->href );
                        hv_store(atV, "NamespaceURI", 12,
                                 C2Sv(ns->href, NULL), NsURIHash);
                    }
                    else {
                        hv_store(atV, "NamespaceURI", 12,
                                 SvREFCNT_inc(empty_sv), NsURIHash);
                    }
                    
                    hv_store(atV, "LocalName", 9,
                             C2Sv(localname, NULL), LocalNameHash);
                    
                    xmlFree(prefix);
                }
                else {
                    hv_store(atV, "Prefix", 6,
                             SvREFCNT_inc(empty_sv), PrefixHash);
                    hv_store(atV, "NamespaceURI", 12,
                             SvREFCNT_inc(empty_sv), NsURIHash);
                    hv_store(atV, "LocalName", 9,
                             C2Sv(name, NULL), LocalNameHash);            
                }
            }
            
            
            if ( localname != NULL && nsURI != NULL ) {
                keyname = PmmGenNsName( localname, nsURI );
            }
            else {
                keyname = PmmGenNsName( name, nsURI );
            }

            len = xmlStrlen( keyname );
            PERL_HASH( atnameHash, keyname, len );
            hv_store(retval, keyname, len, newRV_noinc((SV*)atV), atnameHash );
            if ( nsURI != NULL ) {
                xmlFree( nsURI );
                nsURI = NULL;
            }
            xmlFree( keyname );
            if ( localname != NULL ) {
                xmlFree(localname);
            }
        }
    }
    return retval;
}

HV * 
PmmGenCharDataSV( pTHX_ PmmSAXVectorPtr sax, const xmlChar * data ) {
    HV * retval = newHV();

    if ( data != NULL && xmlStrlen( data ) ) {
        hv_store(retval, "Data", 4,
                 C2Sv(data, NULL), DataHash);
    }

    return retval;
}

HV * 
PmmGenPISV( pTHX_ PmmSAXVectorPtr sax, const xmlChar * target, const xmlChar * data ) {
    HV * retval = newHV();

    if ( target != NULL && xmlStrlen( target ) ) {
        hv_store(retval, "Target", 6,
                 C2Sv(data, NULL), TargetHash);

        if ( data != NULL && xmlStrlen( data ) ) {
            hv_store(retval, "Data", 4,
                     C2Sv(data, NULL), DataHash);
        }
        else {
            hv_store(retval, "Data", 4,
                     C2Sv("", NULL), DataHash);
        }
    }

    return retval;
}

int
PSaxStartDocument(void * ctx)
{
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;
    int count = 0;

    dTHX;
    dSP;
    
    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(sax->parser);
    PUTBACK;

    count = perl_call_pv( "XML::LibXML::_SAXParser::start_document", 0 );

    SPAGAIN;

    PUSHMARK(SP) ;
    XPUSHs(sax->parser);

    if ( ctxt->version != NULL ) {
        XPUSHs(sv_2mortal(C2Sv(ctxt->version, NULL)));
    }

    if ( ctxt->encoding != NULL ) {
        XPUSHs(sv_2mortal(C2Sv(ctxt->encoding, NULL)));
    }

    PUTBACK;
    
    count = perl_call_pv( "XML::LibXML::_SAXParser::xml_decl", 0 );

    FREETMPS ;
    LEAVE ;

    return 1;
}

int
PSaxEndDocument(void * ctx)
{
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;
    int count = 0;

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
PSaxStartElement(void *ctx, const xmlChar * name, const xmlChar** attr) {
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;
    int count = 0;
    SV * attrhash = NULL;
 
    dTHX;
    dSP;
    
    ENTER;
    SAVETMPS;

    PmmExtendNsStack(sax);
    attrhash = (SV*) PmmGenAttributeHashSV(aTHX_  sax, attr );
    
    PUSHMARK(SP) ;
    XPUSHs(sax->parser);
    XPUSHs(newRV_noinc((SV*)PmmGenElementSV(aTHX_ sax,name)));
    XPUSHs(newRV_noinc(attrhash));
    PUTBACK;

    count = perl_call_pv( "XML::LibXML::_SAXParser::start_element", 0 );

    SPAGAIN ;

    FREETMPS ;
    LEAVE ;

    return 1;
}

int
PSaxEndElement(void *ctx, const xmlChar * name) {
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    int count = 0;
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;

    dTHX;
    dSP;
    
    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(sax->parser);
    XPUSHs(sv_2mortal(C2Sv(name, NULL)));
    PUTBACK;

    count = perl_call_pv( "XML::LibXML::_SAXParser::end_element", 0 );

    FREETMPS ;
    LEAVE ;

    PmmNarrowNsStack(sax);

    return 1;
}

int
PSaxCharacters(void *ctx, const xmlChar * ch, int len) {
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;
    int count = 0;

    if ( ch != NULL ) {
        xmlChar * data = xmlStrndup( ch, len );

        dTHX;
        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;
        XPUSHs(sax->parser);
        XPUSHs(newRV_noinc((SV*)PmmGenCharDataSV(aTHX_ sax,data)));
        PUTBACK;

        count = perl_call_pv( "XML::LibXML::_SAXParser::characters", 0 );

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
    if ( ch != NULL ) {
        xmlChar * data = xmlStrdup( ch );

        dTHX;
        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;
        XPUSHs(sax->parser);
        XPUSHs(newRV_noinc((SV*)PmmGenCharDataSV(aTHX_ sax,data)));
        PUTBACK;

        count = perl_call_pv( "XML::LibXML::_SAXParser::comment", 0 );

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
    if ( ch != NULL ) {
        xmlChar * data = xmlStrndup( ch, len );

        dTHX;
        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;
        XPUSHs(sax->parser);
        XPUSHs(newRV_noinc((SV*)PmmGenCharDataSV(aTHX_ sax,data)));
        PUTBACK;

        count = perl_call_pv( "XML::LibXML::_SAXParser::cdata_block", 0 );

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
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;
    int count = 0;

    dTHX;
    dSP;
    
    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(sax->parser);
    XPUSHs(newRV_noinc((SV*)PmmGenPISV(aTHX_ sax, target, data)));

    PUTBACK;

    count = perl_call_pv( "XML::LibXML::_SAXParser::processing_instruction", 0 );

    FREETMPS ;
    LEAVE ;
    
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

    XPUSHs(svMessage);
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

    XPUSHs(svMessage);
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

    XPUSHs(svMessage);
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

