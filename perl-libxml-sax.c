/**
 * perl-libxml-sax.c
 * $Id$
 */

#ifdef __cplusplus
extern "C" {
#endif

#include "EXTERN.h"
#include "perl.h"


#include <stdlib.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/entities.h>
#include <libxml/xmlerror.h>

#ifdef __cplusplus
}
#endif

int
PSaxStartDocument(void * ctx)
{
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    int count = 0;
    dSP;
    
    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(sv_mortalcopy((SV*)ctxt->_private));
    PUTBACK;

    count = perl_call_pv( "XML::LibXML::_SAXParser::start_document", 0 );

    SPAGAIN;

    PUSHMARK(SP) ;
    XPUSHs(sv_mortalcopy((SV*)ctxt->_private));

    if ( ctxt->version != NULL ) 
        XPUSHs(sv_2mortal(newSVpv((char*)ctxt->version, 0)));

    if ( ctxt->encoding != NULL ) 
        XPUSHs(sv_2mortal(newSVpv((char*)ctxt->encoding, 0)));    

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
    int count = 0;

    dSP;
    
    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(sv_mortalcopy((SV*)ctxt->_private));
    PUTBACK;

    count = perl_call_pv( "XML::LibXML::_SAXParser::end_document", 0 );

    FREETMPS ;
    LEAVE ;

    return 1;
}

int
PSaxStartElement(void *ctx, const xmlChar * name, const xmlChar** attr) {
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    int count = 0;

    dSP;
    
    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(sv_mortalcopy((SV*)ctxt->_private));
    XPUSHs(sv_2mortal(newSVpv((char*)name, 0)));

    if ( attr != NULL ) {
        const xmlChar ** ta = attr;
        while ( *ta ) {
            XPUSHs(sv_2mortal(newSVpv((char*)*ta, 0)));
            ta++;
        }
    }

    PUTBACK;

    count = perl_call_pv( "XML::LibXML::_SAXParser::start_element", 0 );

    FREETMPS ;
    LEAVE ;

    return 1;
}

int
PSaxEndElement(void *ctx, const xmlChar * name) {
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    int count = 0;

    dSP;
    
    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(sv_mortalcopy((SV*)ctxt->_private));
    XPUSHs(sv_2mortal(newSVpv((char*)name, 0)));
    PUTBACK;

    count = perl_call_pv( "XML::LibXML::_SAXParser::end_element", 0 );

    FREETMPS ;
    LEAVE ;

    return 1;
}

int
PSaxCharacters(void *ctx, const xmlChar * ch, int len) {
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    int count = 0;
    if ( ch != NULL ) {
        xmlChar * data = xmlStrndup( ch, len );

        dSP;
    
        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;
        XPUSHs(sv_mortalcopy((SV*)ctxt->_private));
        XPUSHs(sv_2mortal(newSVpv((char*)data, 0)));
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
    int count = 0;
    if ( ch != NULL ) {
        xmlChar * data = xmlStrdup( ch );

        dSP;
    
        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;
        XPUSHs(sv_mortalcopy((SV*)ctxt->_private));
        XPUSHs(sv_2mortal(newSVpv((char*)data, 0)));
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
    int count = 0;
    if ( ch != NULL ) {
        xmlChar * data = xmlStrndup( ch, len );

        dSP;
    
        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;
        XPUSHs(sv_mortalcopy((SV*)ctxt->_private));
        XPUSHs(sv_2mortal(newSVpv((char*)data, 0)));
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
    int count = 0;

    dSP;
    
    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(sv_mortalcopy((SV*)ctxt->_private));
    XPUSHs(sv_2mortal(newSVpv((char*)target, 0)));
    XPUSHs(sv_2mortal(newSVpv((char*)data, 0)));
    PUTBACK;

    count = perl_call_pv( "XML::LibXML::_SAXParser::processing_instruction", 0 );

    FREETMPS ;
    LEAVE ;
    
    return 1;
}

xmlSAXHandlerPtr
PSaxGetHandler()
{
    xmlSAXHandlerPtr retval = (xmlSAXHandlerPtr)xmlMalloc(sizeof(xmlSAXHandler));
    memset(retval, 0, sizeof(xmlSAXHandler));

    retval->startDocument = (startDocumentSAXFunc)&PSaxStartDocument;
    retval->endDocument   = (endDocumentSAXFunc)&PSaxEndDocument;

    retval->startElement  = (startElementSAXFunc)&PSaxStartElement;
    retval->endElement    = (endElementSAXFunc)&PSaxEndElement;

    retval->characters    = (charactersSAXFunc)&PSaxCharacters;
    retval->comment       = (commentSAXFunc)&PSaxComment;
    retval->cdataBlock    = (cdataBlockSAXFunc)&PSaxCDATABlock;

    retval->processingInstruction = (processingInstructionSAXFunc)&PSaxProcessingInstruction;

    /* warning functions should be internal */
    retval->warning    = &xmlParserWarning;
    retval->error      = &xmlParserError;
    retval->fatalError = &xmlParserError;

    return retval;
}
