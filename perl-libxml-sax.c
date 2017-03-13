/**
 * perl-libxml-sax.c
 * $Id$
 *
 * This is free software, you may use it and distribute it under the same terms as
 * Perl itself.
 *
 * Copyright 2001-2003 AxKit.com Ltd., 2002-2006 Christian Glahn, 2006-2009 Petr Pajas
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

#include "perl-libxml-sax.h"

#ifdef __cplusplus
}
#endif


/*
   we must call CLEAR_SERROR_HANDLER upon each excurse from
   perl
*/
#define WITH_SERRORS

#ifdef WITH_SERRORS
#define CLEAR_SERROR_HANDLER /*xmlSetStructuredErrorFunc(NULL,NULL);*/
#else
#define CLEAR_SERROR_HANDLER
#endif

#define NSDELIM ':'
/* #define NSDEFAULTURI "http://www.w3.org/XML/1998/namespace" */
#define NSDEFAULTURI "http://www.w3.org/2000/xmlns/"
typedef struct {
    SV * parser;
    xmlNodePtr ns_stack;
    HV * locator;
    xmlDocPtr ns_stack_root;
    SV * handler;
    SV * saved_error;
    struct CBuffer *charbuf;
    int joinchars;
} PmmSAXVector;

typedef PmmSAXVector* PmmSAXVectorPtr;

struct CBufferChunk {
	struct CBufferChunk *next;
	xmlChar *data;
	int len;
};

struct CBuffer {
	struct CBufferChunk *head;
	struct CBufferChunk *tail;
};

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
static U32 PublicIdHash;
static U32 SystemIdHash;

/* helper function C2Sv is ment to work faster than the perl-libxml-mm
   version. this shortcut is useful, because SAX handles only UTF8
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
        retval = NEWSV(0, len+1);
        sv_setpvn(retval, (const char *)string, len );
#ifdef HAVE_UTF8
        SvUTF8_on( retval );
#endif
    }

    return retval;
}

SV*
_C2Sv_len( const xmlChar *string, int len )
{

    dTHX;
    SV *retval = &PL_sv_undef;

    if ( string != NULL ) {
        retval = NEWSV(0, len+1);
        sv_setpvn(retval, (const char *)string, (STRLEN) len );
#ifdef HAVE_UTF8
        SvUTF8_on( retval );
#endif
    }

    return retval;
}

void
PmmSAXInitialize(pTHX)
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
    PERL_HASH(PublicIdHash,   "PublicId",      8);
    PERL_HASH(SystemIdHash,   "SystemId",      8);
}

xmlSAXHandlerPtr PSaxGetHandler();
int PSaxCharactersFlush(void *, struct CBuffer *);


/* Character buffering functions */

struct CBufferChunk * CBufferChunkNew(void) {
	struct CBufferChunk *newchunk = xmlMalloc(sizeof(struct CBufferChunk));
	memset(newchunk, 0, sizeof(struct CBufferChunk));
	return newchunk;
}

struct CBuffer * CBufferNew(void) {
	struct CBuffer *new = xmlMalloc(sizeof(struct CBuffer));
	struct CBufferChunk *newchunk = CBufferChunkNew();

	memset(new, 0, sizeof(struct CBuffer));

	new->head = newchunk;
	new->tail = newchunk;

	return new;
}

void CBufferPurge(struct CBuffer *buffer) {
	struct CBufferChunk *p1;
	struct CBufferChunk *p2;

	if (buffer == NULL || buffer->head->data == NULL) {
		return;
	}

	if ((p1 = buffer->head)) {

		while(p1) {
			p2 = p1->next;

			if (p1->data) {
				xmlFree(p1->data);
			}

			xmlFree(p1);

			p1 = p2;
		}
	}

	buffer->head = CBufferChunkNew();
	buffer->tail = buffer->head;
}

void CBufferFree(struct CBuffer *buffer) {
	struct CBufferChunk *p1;
	struct CBufferChunk *p2;

	if (buffer == NULL) {
		return;
	}

	if ((p1 = buffer->head)) {

		while(p1) {
			p2 = p1->next;

			if (p1->data) {
				xmlFree(p1->data);
			}

			xmlFree(p1);

			p1 = p2;
		}
	}

	xmlFree(buffer);

	return;
}

int CBufferLength(struct CBuffer *buffer) {
	int length = 0;
	struct CBufferChunk *cur;

	for(cur = buffer->head; cur; cur = cur->next) {
		length += cur->len;
	}

	return length;
}

void CBufferAppend(struct CBuffer *buffer, const xmlChar *newstring, int len) {
	xmlChar *copy = xmlMalloc(len);

	memcpy(copy, newstring, len);

	buffer->tail->data = copy;
	buffer->tail->len = len;
	buffer->tail->next = CBufferChunkNew();
	buffer->tail = buffer->tail->next;
}

xmlChar * CBufferCharacters(struct CBuffer *buffer) {
	int length = CBufferLength(buffer);
	xmlChar *new = xmlMalloc(length + 1);
	xmlChar *p = new;
	int copied = 0;
	struct CBufferChunk *cur;

    /* We need this because stderr on some perls requires
     * my_perl. See:
     *
     * https://rt.cpan.org/Public/Bug/Display.html?id=69082
     *
     * */
	dTHX;

	if (buffer->head->data == NULL) {
		return NULL;
	}

	for(cur = buffer->head;cur;cur = cur->next) {
		if (! cur->data) {
			continue;
		}

		if ((copied = copied + cur->len) > length) {
			fprintf(stderr, "string overflow\n");
			abort();
		}

		memcpy(p, cur->data, cur->len);
		p += cur->len;
	}

	new[length] = '\0';

	return new;
}

/* end character buffering functions */


void
PmmSAXInitContext( xmlParserCtxtPtr ctxt, SV * parser, SV * saved_error )
{
    PmmSAXVectorPtr vec = NULL;
    SV ** th;
    SV ** joinchars;

    dTHX;

    CLEAR_SERROR_HANDLER
    vec = (PmmSAXVector*) xmlMalloc( sizeof(PmmSAXVector) );

    vec->ns_stack_root = xmlNewDoc(NULL);
    vec->ns_stack      = xmlNewDocNode(vec->ns_stack_root,
                                       NULL,
                                       (const xmlChar*)"stack",
                                       NULL );

    xmlAddChild((xmlNodePtr)vec->ns_stack_root, vec->ns_stack);

    vec->locator = NULL;

    vec->saved_error = saved_error;

    vec->parser  = SvREFCNT_inc( parser );
    th = hv_fetch( (HV*)SvRV(parser), "HANDLER", 7, 0 );
    if ( th != NULL && SvTRUE(*th) ) {
        vec->handler = SvREFCNT_inc(*th)  ;
    }
    else {
        vec->handler = NULL;
    }

    joinchars = hv_fetch((HV*)SvRV(parser), "JOIN_CHARACTERS", 15, 0);

    if (joinchars != NULL) {
    	vec->joinchars = (SvIV(*joinchars));
    } else {
    	vec->joinchars = 0;
    }

    if (vec->joinchars) {
        vec->charbuf = CBufferNew();
    } else {
    	vec->charbuf = NULL;
    }

    if ( ctxt->sax ) {
        xmlFree( ctxt->sax );
    }
    ctxt->sax = PSaxGetHandler();

    ctxt->_private = (void*)vec;
}

void
PmmSAXCloseContext( xmlParserCtxtPtr ctxt )
{
    PmmSAXVector * vec = (PmmSAXVectorPtr) ctxt->_private;
    dTHX;

    if ( vec->handler != NULL ) {
        SvREFCNT_dec( vec->handler );
        vec->handler = NULL;
    }

    CBufferFree(vec->charbuf);
    vec->charbuf = NULL;

    xmlFree( ctxt->sax );
    ctxt->sax = NULL;

    SvREFCNT_dec( vec->parser );
    vec->parser = NULL;

    xmlFreeDoc( vec->ns_stack_root );
    vec->ns_stack_root = NULL;

    if ( vec->locator != NULL ) {
        SvREFCNT_dec( vec->locator );
        vec->locator = NULL;
    }

    xmlFree( vec );
    ctxt->_private = NULL;
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

    (void) hv_store(param, "NamespaceURI", 12,
             _C2Sv(uri, NULL), NsURIHash);

    if ( prefix != NULL ) {
        (void) hv_store(param, "Prefix", 6,
                 _C2Sv(prefix, NULL), PrefixHash);
    }
    else {
        (void) hv_store(param, "Prefix", 6,
                 _C2Sv((const xmlChar*)"", NULL), PrefixHash);
    }

    PUSHMARK(SP) ;
    XPUSHs(handler);

    rv = newRV_noinc((SV*)param);

    XPUSHs(rv);
    PUTBACK;

    call_method( "start_prefix_mapping", G_SCALAR | G_EVAL | G_DISCARD );
    sv_2mortal(rv);
    if (SvTRUE(ERRSV)) {
        croak_obj;
    }
    FREETMPS ;
    LEAVE ;
    CLEAR_SERROR_HANDLER
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
    (void) hv_store(param, "NamespaceURI", 12,
             _C2Sv(uri, NULL), NsURIHash);

    if ( prefix != NULL ) {
        (void) hv_store(param, "Prefix", 6,
                 _C2Sv(prefix, NULL), PrefixHash);
    }
    else {
        (void) hv_store(param, "Prefix", 6,
                 _C2Sv((const xmlChar *)"", NULL), PrefixHash);
    }

    PUSHMARK(SP) ;
    XPUSHs(handler);


    rv = newRV_noinc((SV*)param);

    XPUSHs(rv);
    PUTBACK;

    call_method( "end_prefix_mapping", G_SCALAR | G_EVAL | G_DISCARD );
    sv_2mortal(rv);
    if (SvTRUE(ERRSV)) {
        croak_obj;
    }

    FREETMPS ;
    LEAVE ;
    CLEAR_SERROR_HANDLER
}

void
PmmExtendNsStack( PmmSAXVectorPtr sax , const xmlChar * name) {
    xmlNodePtr newNS = NULL;
    xmlChar * localname = NULL;
    xmlChar * prefix = NULL;

    localname = xmlSplitQName( NULL, name, &prefix );
    if ( prefix != NULL ) {
        /* check if we can find a namespace with that prefix... */
        xmlNsPtr ns = xmlSearchNs( sax->ns_stack->doc, sax->ns_stack, prefix );

        if ( ns != NULL ) {
            newNS = xmlNewDocNode( sax->ns_stack_root, ns, localname, NULL );
        }
        else {
            newNS = xmlNewDocNode( sax->ns_stack_root, NULL, name, NULL );
        }
    }
    else {
        newNS = xmlNewDocNode( sax->ns_stack_root, NULL, name, NULL );
    }

    if ( newNS != NULL ) {
        xmlAddChild(sax->ns_stack, newNS);
        sax->ns_stack = newNS;
    }

    if ( localname != NULL ) {
        xmlFree( localname ) ;
    }
    if ( prefix != NULL ) {
        xmlFree( prefix );
    }
}

void
PmmNarrowNsStack( PmmSAXVectorPtr sax, SV *handler )
{
    xmlNodePtr parent = sax->ns_stack->parent;
    xmlNsPtr list = sax->ns_stack->nsDef;

    while ( list ) {
        if ( !xmlStrEqual(list->prefix, (const xmlChar*)"xml") ) {
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
    xmlChar * prefix    = NULL;
    xmlChar * localname = NULL;


    if ( sax->ns_stack == NULL ) {
        return;
    }

    ns = xmlNewNs( sax->ns_stack, href, name );

    if ( sax->ns_stack->ns == NULL ) {
        localname = xmlSplitQName( NULL, sax->ns_stack->name, &prefix );

        if ( name != NULL ) {
            if ( xmlStrEqual( prefix , name ) ) {
                xmlChar * oname = (xmlChar*)(sax->ns_stack->name);
                sax->ns_stack->ns = ns;
                xmlFree( oname );
                sax->ns_stack->name = (const xmlChar*) xmlStrdup( localname );
            }
        }
        else if ( prefix == NULL ) {
            sax->ns_stack->ns = ns;
        }
    }

    if ( prefix ) {
        xmlFree( prefix );
    }
    if ( localname ) {
        xmlFree( localname );
    }

    PSaxStartPrefix( sax, name, href, handler );
}

#define XML_STR_NOT_EMPTY(s) ((s)[0] != 0)

HV *
PmmGenElementSV( pTHX_ PmmSAXVectorPtr sax, const xmlChar * name )
{
    HV * retval = newHV();
    xmlChar * localname = NULL;
    xmlChar * prefix    = NULL;

    xmlNsPtr ns = NULL;

    if ( name != NULL && XML_STR_NOT_EMPTY( name )  ) {
        (void) hv_store(retval, "Name", 4,
                 _C2Sv(name, NULL), NameHash);

        localname = xmlSplitQName(NULL, name, &prefix);
        if (localname != NULL) xmlFree(localname);
        ns = PmmGetNsMapping( sax->ns_stack, prefix );
        if (prefix != NULL) xmlFree(prefix);

        if ( ns != NULL ) {
            (void) hv_store(retval, "NamespaceURI", 12,
                     _C2Sv(ns->href, NULL), NsURIHash);
            if ( ns->prefix ) {
                (void) hv_store(retval, "Prefix", 6,
                         _C2Sv(ns->prefix, NULL), PrefixHash);
            }
            else {
                (void) hv_store(retval, "Prefix", 6,
                         _C2Sv((const xmlChar *)"",NULL), PrefixHash);
            }

            (void) hv_store(retval, "LocalName", 9,
                     _C2Sv(sax->ns_stack->name, NULL), LocalNameHash);
        }
        else {
            (void) hv_store(retval, "NamespaceURI", 12,
                     _C2Sv((const xmlChar *)"",NULL), NsURIHash);
            (void) hv_store(retval, "Prefix", 6,
                     _C2Sv((const xmlChar *)"",NULL), PrefixHash);
            (void) hv_store(retval, "LocalName", 9,
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

    retval =xmlStrncat( retval, (const xmlChar *)"{", 1 );
    if ( nsURI != NULL ) {
        urilen = xmlStrlen( nsURI );
        retval =xmlStrncat( retval, nsURI, urilen );
    }
    retval = xmlStrncat( retval, (const xmlChar *)"}", 1 );
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

            if ( name != NULL && XML_STR_NOT_EMPTY( name ) ) {
                localname = xmlSplitQName(NULL, name, &prefix);

                (void) hv_store(atV, "Name", 4,
                         _C2Sv(name, NULL), NameHash);
                if ( value != NULL ) {
                    (void) hv_store(atV, "Value", 5,
                             _C2Sv(value, NULL), ValueHash);
                }

                if ( xmlStrEqual( (const xmlChar *)"xmlns", name ) ) {
                    /* a default namespace */
                    PmmAddNamespace( sax, NULL, value, handler);
                    /* nsURI = (const xmlChar*)NSDEFAULTURI; */
                    nsURI = NULL;
                    (void) hv_store(atV, "Name", 4,
                             _C2Sv(name, NULL), NameHash);

                    (void) hv_store(atV, "Prefix", 6,
                             _C2Sv((const xmlChar *)"", NULL), PrefixHash);
                    (void) hv_store(atV, "LocalName", 9,
                             _C2Sv(name,NULL), LocalNameHash);
                    (void) hv_store(atV, "NamespaceURI", 12,
                             _C2Sv((const xmlChar *)"", NULL), NsURIHash);

                }
                else if (xmlStrncmp((const xmlChar *)"xmlns:", name, 6 ) == 0 ) {
                    PmmAddNamespace( sax,
                                     localname,
                                     value,
                                     handler);

                    nsURI = (const xmlChar*)NSDEFAULTURI;

                    (void) hv_store(atV, "Prefix", 6,
                             _C2Sv(prefix, NULL), PrefixHash);
                    (void) hv_store(atV, "LocalName", 9,
                             _C2Sv(localname, NULL), LocalNameHash);
                    (void) hv_store(atV, "NamespaceURI", 12,
                             _C2Sv((const xmlChar *)NSDEFAULTURI,NULL),
                             NsURIHash);
                }
                else if ( prefix != NULL
                          && (ns = PmmGetNsMapping( sax->ns_stack, prefix ) ) ) {
                    nsURI = ns->href;

                    (void) hv_store(atV, "NamespaceURI", 12,
                             _C2Sv(ns->href, NULL), NsURIHash);
                    (void) hv_store(atV, "Prefix", 6,
                             _C2Sv(ns->prefix, NULL), PrefixHash);
                    (void) hv_store(atV, "LocalName", 9,
                             _C2Sv(localname, NULL), LocalNameHash);
                }
                else {
                    nsURI = NULL;
                    (void) hv_store(atV, "NamespaceURI", 12,
                             _C2Sv((const xmlChar *)"", NULL), NsURIHash);
                    (void) hv_store(atV, "Prefix", 6,
                             _C2Sv((const xmlChar *)"", NULL), PrefixHash);
                    (void) hv_store(atV, "LocalName", 9,
                             _C2Sv(name, NULL), LocalNameHash);
                }

                keyname = PmmGenNsName( localname != NULL ? localname : name,
                                        nsURI );

                len = xmlStrlen( keyname );
                PERL_HASH( atnameHash, (const char *)keyname, len );
                (void) hv_store(retval,
                         (const char *)keyname,
                         len,
                         newRV_noinc((SV*)atV),
                         atnameHash );

                if ( keyname != NULL ) {
                    xmlFree( keyname );
                }
                if ( localname != NULL ) {
                    xmlFree(localname);
                }
                localname = NULL;
                if ( prefix != NULL ) {
                    xmlFree( prefix );
                }
                prefix    = NULL;

            }
        }
    }

    return retval;
}

HV *
PmmGenCharDataSV( pTHX_ PmmSAXVectorPtr sax, const xmlChar * data, int len )
{
    HV * retval = newHV();

    if ( data != NULL && XML_STR_NOT_EMPTY( data ) ) {
        (void) hv_store(retval, "Data", 4,
                 _C2Sv_len(data, len), DataHash);
    }

    return retval;
}

HV *
PmmGenPISV( pTHX_ PmmSAXVectorPtr sax,
            const xmlChar * target,
            const xmlChar * data )
{
    HV * retval = newHV();

    if ( target != NULL && XML_STR_NOT_EMPTY( target ) ) {
        (void) hv_store(retval, "Target", 6,
                 _C2Sv(target, NULL), TargetHash);

        if ( data != NULL && XML_STR_NOT_EMPTY( data ) ) {
            (void) hv_store(retval, "Data", 4,
                     _C2Sv(data, NULL), DataHash);
        }
        else {
            (void) hv_store(retval, "Data", 4,
                     _C2Sv((const xmlChar *)"", NULL), DataHash);
        }
    }

    return retval;
}

HV *
PmmGenDTDSV( pTHX_ PmmSAXVectorPtr sax,
	     const xmlChar * name,
	     const xmlChar * publicId,
	     const xmlChar * systemId )
{
    HV * retval = newHV();
    if ( name != NULL && XML_STR_NOT_EMPTY( name ) ) {
      (void) hv_store(retval, "Name", 4,
	       _C2Sv(name, NULL), NameHash);
    }
    if ( publicId != NULL && XML_STR_NOT_EMPTY( publicId ) ) {
      (void) hv_store(retval, "PublicId", 8,
	       _C2Sv(publicId, NULL), PublicIdHash);
    }
    if ( systemId != NULL && XML_STR_NOT_EMPTY( systemId ) ) {
      (void) hv_store(retval, "SystemId", 8,
	       _C2Sv(systemId, NULL), SystemIdHash);
    }
    return retval;
}

HV *
PmmGenLocator( xmlSAXLocatorPtr loc)
{
    dTHX;
    HV * locator = newHV();

    const xmlChar * PublicId = loc->getPublicId(NULL);
    const xmlChar * SystemId = loc->getSystemId(NULL);

    if ( PublicId != NULL && XML_STR_NOT_EMPTY( PublicId ) ) {
      (void) hv_store(locator, "PublicId", 8,
           newSVpv((char *)PublicId, 0), 0);
    }

    if ( SystemId != NULL && XML_STR_NOT_EMPTY( SystemId ) ) {
      (void) hv_store(locator, "SystemId", 8,
           newSVpv((char *)SystemId, 0), 0);
    }

    return locator;
}


void
PmmUpdateLocator( xmlParserCtxtPtr ctxt )
{
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;

    if (sax->locator == NULL) {
        return;
    }

    dTHX;

    (void) hv_store(sax->locator, "LineNumber", 10,
         newSViv(ctxt->input->line), 0);

    (void) hv_store(sax->locator, "ColumnNumber", 12,
         newSViv(ctxt->input->col), 0);

    const xmlChar * encoding = ctxt->input->encoding;
    const xmlChar * version = ctxt->input->version;

    if ( encoding != NULL && XML_STR_NOT_EMPTY( encoding ) ) {
      (void) hv_store(sax->locator, "Encoding", 8,
           newSVpv((char *)encoding, 0), 0);
    }

    if ( version != NULL && XML_STR_NOT_EMPTY( version ) ) {
      (void) hv_store(sax->locator, "XMLVersion", 10,
           newSVpv((char *)version, 0), 0);
    }
}

int
PSaxSetDocumentLocator(void *ctx, xmlSAXLocatorPtr loc)
{
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr  sax  = (PmmSAXVectorPtr)ctxt->_private;
    dTHX;
    HV* empty;
    SV * handler          = sax->handler;
    SV * rv;

    dSP;

    if (sax->joinchars)
    {
        PSaxCharactersFlush(ctxt, sax->charbuf);
    }

    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;

    XPUSHs(handler);

    sax->locator = PmmGenLocator(loc);

    rv = newRV_inc((SV*)sax->locator);
    XPUSHs( rv);

    PUTBACK;

    call_method( "set_document_locator", G_SCALAR | G_EVAL | G_DISCARD );
    sv_2mortal(rv) ;

    if (SvTRUE(ERRSV)) {
        croak_obj;
    }

    FREETMPS ;
    LEAVE ;
    CLEAR_SERROR_HANDLER
    return 1;
}

int
PSaxStartDocument(void * ctx)
{
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax   = (PmmSAXVectorPtr)ctxt->_private;
    dTHX;
    HV* empty;
    SV * handler         = sax->handler;

    SV * rv;
    if ( handler != NULL ) {

        PmmUpdateLocator(ctx);

        dSP;

        ENTER;
        SAVETMPS;

        empty = newHV();
        PUSHMARK(SP) ;
        XPUSHs(handler);
        XPUSHs(sv_2mortal(newRV_noinc((SV*)empty)));
        PUTBACK;

        call_method( "start_document", G_SCALAR | G_EVAL | G_DISCARD );
        if (SvTRUE(ERRSV)) {
            croak_obj;
        }

        SPAGAIN;

        PUSHMARK(SP) ;


        XPUSHs(handler);

        empty = newHV();
        if ( ctxt->version != NULL ) {
            (void) hv_store(empty, "Version", 7,
                     _C2Sv(ctxt->version, NULL), VersionHash);
        }
        else {
            (void) hv_store(empty, "Version", 7,
                     _C2Sv((const xmlChar *)"1.0", NULL), VersionHash);
        }

        if ( ctxt->input->encoding != NULL ) {
            (void) hv_store(empty, "Encoding", 8,
                     _C2Sv(ctxt->input->encoding, NULL), EncodingHash);
        }

        rv = newRV_noinc((SV*)empty);
        XPUSHs( rv);

        PUTBACK;

        call_method( "xml_decl", G_SCALAR | G_EVAL | G_DISCARD );
	CLEAR_SERROR_HANDLER
        sv_2mortal(rv);
        if (SvTRUE(ERRSV)) {
            croak_obj;
        }

        FREETMPS ;
        LEAVE ;
    }
    CLEAR_SERROR_HANDLER
    return 1;
}

int
PSaxEndDocument(void * ctx)
{
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr  sax  = (PmmSAXVectorPtr)ctxt->_private;

    dTHX;
    dSP;

    PmmUpdateLocator(ctx);

    if (sax->joinchars)
    {
        PSaxCharactersFlush(ctxt, sax->charbuf);
    }


    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(sax->parser);
    PUTBACK;

    call_pv( "XML::LibXML::_SAXParser::end_document", G_SCALAR | G_EVAL | G_DISCARD );
    if (SvTRUE(ERRSV)) {
        croak_obj;
    }

    FREETMPS ;
    LEAVE ;
    CLEAR_SERROR_HANDLER
    return 1;
}

int
PSaxStartElement(void *ctx, const xmlChar * name, const xmlChar** attr)
{
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr  sax  = (PmmSAXVectorPtr)ctxt->_private;
    dTHX;
    HV * attrhash         = NULL;
    HV * element          = NULL;
    SV * handler          = sax->handler;
    SV * rv;
    SV * arv;

    dSP;

    PmmUpdateLocator(ctx);

    if (sax->joinchars)
    {
        PSaxCharactersFlush(ctxt, sax->charbuf);
    }

    ENTER;
    SAVETMPS;

    PmmExtendNsStack(sax, name);

    attrhash = PmmGenAttributeHashSV(aTHX_ sax, attr, handler );
    element  = PmmGenElementSV(aTHX_ sax, name);

    arv = newRV_noinc((SV*)attrhash);
    (void) hv_store( element,
              "Attributes",
              10,
              arv,
              AttributesHash );

    PUSHMARK(SP) ;

    XPUSHs(handler);
    rv = newRV_noinc((SV*)element);
    XPUSHs(rv);
    PUTBACK;

    call_method( "start_element", G_SCALAR | G_EVAL | G_DISCARD );
    sv_2mortal(rv) ;

    if (SvTRUE(ERRSV)) {
        croak_obj;
    }

    FREETMPS ;
    LEAVE ;
    CLEAR_SERROR_HANDLER
    return 1;
}

int
PSaxEndElement(void *ctx, const xmlChar * name) {
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr  sax  = (PmmSAXVectorPtr)ctxt->_private;
    dTHX;
    SV * handler         = sax->handler;
    SV * rv;
    HV * element;

    dSP;

    PmmUpdateLocator(ctx);

    if (sax->joinchars)
    {
        PSaxCharactersFlush(ctxt, sax->charbuf);
    }

    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(handler);

    element = PmmGenElementSV(aTHX_ sax, name);
    rv = newRV_noinc((SV*)element);

    XPUSHs(rv);
    PUTBACK;

    call_method( "end_element", G_SCALAR | G_EVAL | G_DISCARD );
    sv_2mortal(rv);

    if (SvTRUE(ERRSV)) {
        croak_obj;
    }

    FREETMPS ;
    LEAVE ;

    PmmNarrowNsStack(sax, handler);
    CLEAR_SERROR_HANDLER
    return 1;
}

int
PSaxCharactersDispatch(void *ctx, const xmlChar * ch, int len) {
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;
    dTHX;
    HV* element;
    SV * handler;
    SV * rv = NULL;

    if ( sax == NULL ) {
/*         warn( "lost my sax context!? ( %s, %d )\n", ch, len ); */
        return 0;
    }

    handler = sax->handler;

    if ( ch != NULL && handler != NULL ) {

        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;

        XPUSHs(handler);
        element = PmmGenCharDataSV(aTHX_ sax, ch, len );

        rv = newRV_noinc((SV*)element);
        XPUSHs(rv);
        sv_2mortal(rv);

        PUTBACK;

        call_method( "characters", G_SCALAR | G_EVAL | G_DISCARD );

        if (SvTRUE(ERRSV)) {
            croak_obj;
        }
        FREETMPS ;
        LEAVE ;

    }
    CLEAR_SERROR_HANDLER;
    return 1;
}

int PSaxCharactersFlush (void *ctx, struct CBuffer *buffer) {
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;
    xmlChar *ch;
    int len;

    if (buffer->head->data == NULL) {
        return 1;
    }

    ch = CBufferCharacters(sax->charbuf);
    len = CBufferLength(sax->charbuf);

    CBufferPurge(buffer);

    return PSaxCharactersDispatch(ctx, ch, len);
}

int PSaxCharacters (void *ctx, const xmlChar * ch, int len) {
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;

    PmmUpdateLocator(ctx);

    if (sax->joinchars) {
        struct CBuffer *buffer = sax->charbuf;
        CBufferAppend(buffer, ch, len);
        return 1;
    }

    return PSaxCharactersDispatch(ctx, ch, len);
}

int
PSaxComment(void *ctx, const xmlChar * ch) {
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;
    dTHX;
    HV* element;
    SV * handler = sax->handler;

    PmmUpdateLocator(ctx);

    SV * rv = NULL;

    if ( ch != NULL && handler != NULL ) {
        dSP;

        int len = xmlStrlen( ch );

        if (sax->joinchars)
        {
            PSaxCharactersFlush(ctxt, sax->charbuf);
        }

        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;
        XPUSHs(handler);
        element = PmmGenCharDataSV(aTHX_ sax, ch, len);

        rv = newRV_noinc((SV*)element);
        XPUSHs(rv);
        PUTBACK;

        call_method( "comment", G_SCALAR | G_EVAL | G_DISCARD );
        sv_2mortal(rv);

        if (SvTRUE(ERRSV)) {
            croak_obj;
        }

        FREETMPS ;
        LEAVE ;
    }
    CLEAR_SERROR_HANDLER
    return 1;
}

int
PSaxCDATABlock(void *ctx, const xmlChar * ch, int len) {
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;
    dTHX;

    PmmUpdateLocator(ctx);

    HV* element;
    SV * handler = sax->handler;

    SV * rv = NULL;

    if ( ch != NULL && handler != NULL ) {
        dSP;

        if (sax->joinchars)
        {
            PSaxCharactersFlush(ctxt, sax->charbuf);
        }


        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;
        XPUSHs(handler);
        PUTBACK;
        call_method( "start_cdata", G_SCALAR | G_EVAL | G_DISCARD );
        if (SvTRUE(ERRSV)) {
            croak_obj;
        }

        SPAGAIN;
        PUSHMARK(SP) ;

        XPUSHs(handler);
        element = PmmGenCharDataSV(aTHX_ sax, ch, len);

        rv = newRV_noinc((SV*)element);
        XPUSHs(rv);
        PUTBACK;

        call_method( "characters", G_SCALAR | G_EVAL | G_DISCARD);
        if (SvTRUE(ERRSV)) {
            croak_obj;
        }

        SPAGAIN;
        PUSHMARK(SP) ;

        XPUSHs(handler);
        PUTBACK;

        call_method( "end_cdata", G_SCALAR | G_EVAL | G_DISCARD );
        sv_2mortal(rv);

        if (SvTRUE(ERRSV)) {
            croak_obj;
        }

        FREETMPS ;
        LEAVE ;

    }
    CLEAR_SERROR_HANDLER
    return 1;

}

int
PSaxProcessingInstruction( void * ctx, const xmlChar * target, const xmlChar * data )
{
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax   = (PmmSAXVectorPtr)ctxt->_private;
    dTHX;
    SV * handler          = sax->handler;

    PmmUpdateLocator(ctx);

    SV * element;
    SV * rv = NULL;

    if ( handler != NULL ) {
        dSP;

        if (sax->joinchars)
        {
            PSaxCharactersFlush(ctxt, sax->charbuf);
        }

        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;
        XPUSHs(handler);
        element = (SV*)PmmGenPISV(aTHX_ sax, (const xmlChar *)target, data);
        rv = newRV_noinc((SV*)element);
        XPUSHs(rv);

        PUTBACK;

        call_method( "processing_instruction", G_SCALAR | G_EVAL | G_DISCARD );

        sv_2mortal(rv);

        if (SvTRUE(ERRSV)) {
            croak_obj;
        }

        FREETMPS ;
        LEAVE ;
    }
    CLEAR_SERROR_HANDLER
    return 1;
}

void PSaxExternalSubset (void * ctx,
			const xmlChar * name,
			const xmlChar * ExternalID,
			const xmlChar * SystemID)
{
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax   = (PmmSAXVectorPtr)ctxt->_private;
    PmmUpdateLocator(ctx);

    dTHX;
    SV * handler          = sax->handler;

    SV * element;
    SV * rv = NULL;

    if ( handler != NULL ) {
        dSP;

        ENTER;
        SAVETMPS;

        PUSHMARK(SP) ;
        XPUSHs(handler);
        element = (SV*)PmmGenDTDSV(aTHX_ sax,
				   name,
				   ExternalID,
				   SystemID);
        rv = newRV_noinc((SV*)element);
        XPUSHs(rv);

        PUTBACK;

        call_method( "start_dtd", G_SCALAR | G_EVAL | G_DISCARD );
        sv_2mortal(rv);

        if (SvTRUE(ERRSV)) {
            croak_obj;
        }

        PUSHMARK(SP) ;
        XPUSHs(handler);
        rv = newRV_noinc((SV*)newHV()); /* empty */
        XPUSHs(rv);

        PUTBACK;

        call_method( "end_dtd", G_SCALAR | G_EVAL | G_DISCARD );

        FREETMPS ;
        LEAVE ;
    }
    CLEAR_SERROR_HANDLER
    return;
}


/*

void PSaxInternalSubset (void * ctx,
			const xmlChar * name,
			const xmlChar * ExternalID,
			const xmlChar * SystemID)
{
  // called before ExternalSubset
  // if used, how do we generate the correct start_dtd ?
}

void PSaxElementDecl (void *ctx, const xmlChar *name,
		      int type,
		      xmlElementContentPtr content) {
  // this one is  not easy to implement
  // since libxml2 has no (reliable) public method
  // for dumping xmlElementContent :-(
}

void
PSaxAttributeDecl (void * ctx,
		   const xmlChar * elem,
		   const xmlChar * fullname,
		   int type,
		   int def,
		   const xmlChar * defaultValue,
		   xmlEnumerationPtr tree)
{
}

void
PSaxEntityDecl (void * ctx,
		const xmlChar * name,
		int type,
		const xmlChar * publicId,
		const xmlChar * systemId,
		xmlChar * content)
{
}

void
PSaxNotationDecl (void * ctx,
		  const xmlChar * name,
		  const xmlChar * publicId,
		  const xmlChar * systemId)
{
}

void
PSaxUnparsedEntityDecl (void * ctx,
			const xmlChar * name,
			const xmlChar * publicId,
			const xmlChar * systemId,
			const xmlChar * notationName)
{
}
*/

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
    sv_vsetpvfn(svMessage,
                msg,
                xmlStrlen((const xmlChar *)msg),
                &args,
                NULL,
                0,
                NULL);
    va_end(args);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(sax->parser);

    XPUSHs(sv_2mortal(svMessage));
    XPUSHs(sv_2mortal(newSViv(ctxt->input->line)));
    XPUSHs(sv_2mortal(newSViv(ctxt->input->col)));

    PUTBACK;

    call_pv( "XML::LibXML::_SAXParser::warning", G_SCALAR | G_EVAL | G_DISCARD );

    if (SvTRUE(ERRSV)) {
        croak_obj;
    }

    FREETMPS ;
    LEAVE ;
    CLEAR_SERROR_HANDLER
    return 1;
}


int
PmmSaxError(void * ctx, const char * msg, ...)
{
    xmlParserCtxtPtr ctxt = (xmlParserCtxtPtr)ctx;
    PmmSAXVectorPtr sax = (PmmSAXVectorPtr)ctxt->_private;

    va_list args;
    SV * svMessage;

#if LIBXML_VERSION > 20600
    xmlErrorPtr last_err = xmlCtxtGetLastError( ctxt );
#endif
    dTHX;
    dSP;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;

    XPUSHs(sax->parser);

    svMessage = NEWSV(0,512);

    va_start(args, msg);
    sv_vsetpvfn(svMessage, msg, xmlStrlen((const xmlChar *)msg), &args, NULL, 0, NULL);
    va_end(args);
    if (SvOK(sax->saved_error)) {
      sv_catsv( sax->saved_error, svMessage );
    } else {
      sv_setsv( sax->saved_error, svMessage );
    }
    XPUSHs(sv_2mortal(svMessage));
    XPUSHs(sv_2mortal(newSViv(ctxt->input->line)));
    XPUSHs(sv_2mortal(newSViv(ctxt->input->col)));

    PUTBACK;
#if LIBXML_VERSION > 20600
    /*
       this is a workaround: at least some versions of libxml2 didn't not call
       the fatalError callback at all
    */
    if (last_err && last_err->level == XML_ERR_FATAL) {
      call_pv( "XML::LibXML::_SAXParser::fatal_error", G_SCALAR | G_EVAL | G_DISCARD );
    } else {
      call_pv( "XML::LibXML::_SAXParser::error", G_SCALAR | G_EVAL | G_DISCARD );
    }
#else
    /* actually, we do not know if it is a fatal error or not */
    call_pv( "XML::LibXML::_SAXParser::fatal_error", G_SCALAR | G_EVAL | G_DISCARD );
#endif
    if (SvTRUE(ERRSV)) {
        croak_obj;
    }

    FREETMPS ;
    LEAVE ;
    CLEAR_SERROR_HANDLER
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
    sv_vsetpvfn(svMessage, msg, xmlStrlen((const xmlChar *)msg), &args, NULL, 0, NULL);
    va_end(args);

    ENTER;
    SAVETMPS;

    PUSHMARK(SP) ;
    XPUSHs(sax->parser);

    if (SvOK(sax->saved_error)) {
      sv_catsv( sax->saved_error, svMessage );
    } else {
      sv_setsv( sax->saved_error, svMessage );
    }

    XPUSHs(sv_2mortal(svMessage));
    XPUSHs(sv_2mortal(newSViv(ctxt->input->line)));
    XPUSHs(sv_2mortal(newSViv(ctxt->input->col)));

    PUTBACK;
    call_pv( "XML::LibXML::_SAXParser::fatal_error", G_SCALAR | G_EVAL | G_DISCARD );
    if (SvTRUE(ERRSV)) {
        croak_obj;
    }

    FREETMPS ;
    LEAVE ;
    CLEAR_SERROR_HANDLER
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

    retval->setDocumentLocator = (setDocumentLocatorSAXFunc)&PSaxSetDocumentLocator;

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

    retval->externalSubset = (externalSubsetSAXFunc)&PSaxExternalSubset;

    /*
    retval->internalSubset = (internalSubsetSAXFunc)&PSaxInternalSubset;
    retval->elementDecl = (elementDeclSAXFunc)&PSaxElementDecl;
    retval->entityDecl  = (entityDeclSAXFunc)&PSaxEntityDecl;
    retval->notationDecl  = (notationDeclSAXFunc)&PSaxNotationDecl;
    retval->attributeDecl  = (attributeDeclSAXFunc)&PSaxAttributeDecl;
    retval->unparsedEntityDecl  = (unparsedEntityDeclSAXFunc)&PSaxUnparsedEntityDecl;
    */

    return retval;
}

