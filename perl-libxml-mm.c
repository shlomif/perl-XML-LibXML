/**
 * perl-libxml-mm.c
 * $Id$
 *
 * Basic concept:
 * perl varies in the implementation of UTF8 handling. this header (together
 * with the c source) implements a few functions, that can be used from within
 * the core module inorder to avoid cascades of c pragmas
 */

#ifdef __cplusplus
extern "C" {
#endif

#include <stdarg.h>
#include <stdlib.h>

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <libxml/parser.h>
#include <libxml/tree.h>

#ifdef __cplusplus
}
#endif

#ifdef XS_WARNINGS
#define xs_warn(string) warn(string) 
#else
#define xs_warn(string)
#endif

/**
 * this is a wrapper function that does the type evaluation for the 
 * node. this makes the code a little more readable in the .XS
 * 
 * the code is not really portable, but i think we'll avoid some 
 * memory leak problems that way.
 **/
const char*
PmmNodeTypeName( xmlNodePtr elem ){
    const char *name = "XML::LibXML::Node";

    if ( elem != NULL ) {
        char * ptrHlp;
        switch ( elem->type ) {
        case XML_ELEMENT_NODE:
            name = "XML::LibXML::Element";   
            break;
        case XML_TEXT_NODE:
            name = "XML::LibXML::Text";
            break;
        case XML_COMMENT_NODE:
            name = "XML::LibXML::Comment";
            break;
        case XML_CDATA_SECTION_NODE:
            name = "XML::LibXML::CDATASection";
            break;
        case XML_ATTRIBUTE_NODE:
            name = "XML::LibXML::Attr"; 
            break;
        case XML_DOCUMENT_NODE:
        case XML_HTML_DOCUMENT_NODE:
            name = "XML::LibXML::Document";
            break;
        case XML_DOCUMENT_FRAG_NODE:
            name = "XML::LibXML::DocumentFragment";
            break;
        case XML_NAMESPACE_DECL:
            name = "XML::LibXML::Namespace";
            break;
        case XML_DTD_NODE:
            name = "XML::LibXML::Dtd";
            break;
        case XML_PI_NODE:
            name = "XML::LibXML::PI";
            break;
        default:
            name = "XML::LibXML::Node";
            break;
        };
        return name;
    }
    return "";
}

/*
 * @node: Reference to the node the structure proxies
 * @owner: libxml defines only the document, but not the node owner
 *         (in case of document fragments, they are not the same!)
 * @count: this is the internal reference count!
 *
 * Since XML::LibXML will not know, is a certain node is already
 * defined in the perl layer, it can't shurely tell when a node can be
 * safely be removed from the memory. This structure helps to keep
 * track how intense the nodes of a document are used and will not
 * delete the nodes unless they are not refered from somewhere else.
 */
struct _ProxyNode {
    xmlNodePtr node;
    xmlNodePtr owner;
    int count;
};

/* helper type for the proxy structure */
typedef struct _ProxyNode ProxyNode;

/* pointer to the proxy structure */
typedef ProxyNode* ProxyNodePtr;

/* this my go only into the header used by the xs */
#define SvPROXYNODE(x) ((ProxyNodePtr)SvIV(SvRV(x)))
#define SvNAMESPACE(x) ((xmlNsPtr)SvIV(SvRV(x)))

#define PmmREFCNT(node)      node->count
#define PmmREFCNT_inc(node)  node->count++
#define PmmNODE(thenode)     thenode->node
#define PmmOWNER(node)       node->owner
#define PmmOWNERPO(node)     ((node && PmmOWNER(node)) ? (ProxyNodePtr)PmmOWNER(node)->_private : node)

/* creates a new proxy node from a given node. this function is aware
 * about the fact that a node may already has a proxy structure.
 */
ProxyNodePtr
PmmNewNode(xmlNodePtr node)
{
    ProxyNodePtr proxy;

    if ( node->_private == NULL ) {
        proxy = (ProxyNodePtr)malloc(sizeof(ProxyNode));
        /* proxy = (ProxyNodePtr)Newz(0, proxy, 0, ProxyNode); */
        if (proxy != NULL) {
            proxy->node  = node;
            proxy->owner   = NULL;
            proxy->count   = 0;
            node->_private = (void*) proxy;
        }
    }
    else {
        proxy = (ProxyNodePtr)node->_private;
    }
    return proxy;
}

ProxyNodePtr
PmmNewFragment(xmlDocPtr doc) 
{
    ProxyNodePtr retval;
    xmlNodePtr frag = NULL;

    xs_warn("new frag\n");
    frag   = xmlNewDocFragment( doc );
    retval = PmmNewNode(frag);

    if ( doc ) {
        xs_warn("inc document\n");
        PmmREFCNT_inc(((ProxyNodePtr)doc->_private));
        retval->owner = (xmlNodePtr)doc;
    }

    return retval;
}

/* frees the node if nessecary. this method is aware, that libxml2
 * has several diffrent nodetypes.
 */
void
PmmFreeNode( xmlNodePtr node )
{
    switch( node->type ) {
    case XML_DOCUMENT_NODE:
    case XML_HTML_DOCUMENT_NODE:
        xs_warn("XML_DOCUMENT_NODE\n");
        xmlFreeDoc( (xmlDocPtr) node );
        break;
    case XML_ATTRIBUTE_NODE:
        xs_warn("XML_ATTRIBUTE_NODE\n");
        if ( node->parent == NULL ) {
            xs_warn( "free node\n");
            node->ns = NULL;
            xmlFreeProp( (xmlAttrPtr) node );
        }
        break;
    case XML_DTD_NODE:
        if ( node->doc ) {
            if ( node->doc->extSubset != (xmlDtdPtr)node 
                 && node->doc->intSubset != (xmlDtdPtr)node ) {
                xs_warn( "XML_DTD_NODE\n");
                node->doc = NULL;
                xmlFreeDtd( (xmlDtdPtr)node );
            }
        }
        break;
    case XML_DOCUMENT_FRAG_NODE:
        xs_warn("XML_DOCUMENT_FRAG_NODE\n");
    default:
        xmlFreeNode( node);
        break;
    }
}

/* decrements the proxy counter. if the counter becomes zero or less,
   this method will free the proxy node. If the node is part of a
   subtree, PmmREFCNT_def will fix the reference counts and delete
   the subtree if it is not required any more.
 */
int
PmmREFCNT_dec( ProxyNodePtr node ) 
{ 
    xmlNodePtr libnode;
    ProxyNodePtr owner; 
    int retval = 0;
    if ( node ) {
        retval = PmmREFCNT(node)--;
        if ( PmmREFCNT(node) <= 0 ) {
            xs_warn( "NODE DELETATION\n" );
            libnode = PmmNODE( node );
            libnode->_private = NULL;
            PmmNODE( node ) = NULL;
            if ( PmmOWNER(node) && PmmOWNERPO(node) ) {
                xs_warn( "DOC NODE!\n" );
                owner = PmmOWNERPO(node);
                PmmOWNER( node ) = NULL;
                if ( libnode->parent == NULL ) {
                    /* this is required if the node does not directly
                     * belong to the document tree
                     */
                    xs_warn( "REAL DELETE" );
                    PmmFreeNode( libnode );
                }            
                PmmREFCNT_dec( owner );
            }
            else {
                xs_warn( "STANDALONE REAL DELETE" );
                PmmFreeNode( libnode );
            }
            free( node );
        }
    }
    return retval;
}

/* @node: the node that should be wrapped into a SV
 * @owner: perl instance of the owner node (may be NULL)
 *
 * This function will create a real perl instance of a given node.
 * the function is called directly by the XS layer, to generate a perl
 * instance of the node. All node reference counts are updated within
 * this function. Therefore this function returns a node that can
 * directly be used as output.
 *
 * if @ower is NULL or undefined, the node is ment to be the root node
 * of the tree. this node will later be used as an owner of other
 * nodes.
 */
SV*
PmmNodeToSv( xmlNodePtr node, ProxyNodePtr owner ) 
{
    ProxyNodePtr dfProxy= NULL;
    SV * retval = &PL_sv_undef;
    const char * CLASS = "XML::LibXML::Node";

    if ( node != NULL ) {
        /* find out about the class */
        CLASS = PmmNodeTypeName( node );
        xs_warn(" return new perl node\n");
        xs_warn( CLASS );

        if ( node->_private ) {
            dfProxy = PmmNewNode(node);
        }
        else {
            dfProxy = PmmNewNode(node);
            if ( dfProxy != NULL ) {
                if ( owner != NULL ) {
                    dfProxy->owner = PmmNODE( owner );
                    PmmREFCNT_inc( owner );
                }
                else {
                   xs_warn("node contains himself");
                }
            }
            else {
                xs_warn("proxy creation failed!\n");
            }
        }

        retval = NEWSV(0,0);
        sv_setref_pv( retval, CLASS, (void*)dfProxy );
        PmmREFCNT_inc(dfProxy);            
    }         
    else {
        xs_warn( "no node found!" );
    }

    return retval;
}

/* extracts the libxml2 node from a perl reference
 */
xmlNodePtr
PmmSvNode( SV* perlnode ) 
{
    xmlNodePtr retval = NULL;

    if ( perlnode != NULL
         && perlnode != &PL_sv_undef
         && sv_derived_from(perlnode, "XML::LibXML::Node")
         && SvPROXYNODE(perlnode) != NULL  ) {
        retval = PmmNODE( SvPROXYNODE(perlnode) ) ;
    }

    return retval;
}


/* extracts the libxml2 owner node from a perl reference
 */
xmlNodePtr
PmmSvOwner( SV* perlnode ) 
{
    xmlNodePtr retval = NULL;
    if ( perlnode != NULL
         && perlnode != &PL_sv_undef
         && SvPROXYNODE(perlnode) != NULL  ) {
        retval = PmmOWNER( SvPROXYNODE(perlnode) );
    }
    return retval;
}

/* reverse to PmmSvOwner(). sets the owner of the current node. this
 * will increase the proxy count of the owner.
 */
SV* 
PmmSetSvOwner( SV* perlnode, SV* extra )
{
    if ( perlnode != NULL && perlnode != &PL_sv_undef ) {        
        PmmOWNER( SvPROXYNODE(perlnode)) = PmmNODE( SvPROXYNODE(extra) );
        PmmREFCNT_inc( SvPROXYNODE(extra) );
    }
    return perlnode;
}

void
PmmFixOwnerList( xmlNodePtr list, ProxyNodePtr parent )
{
    if ( list ) {
        xmlNodePtr iterator;
        for ( iterator = list; iterator != NULL ; iterator = iterator->next ){
            if ( iterator->_private != NULL ) {
                PmmFixOwner( (ProxyNodePtr)iterator->_private, parent );
            }
            else {
                if ( iterator->type != XML_ATTRIBUTE_NODE
                     &&  iterator->properties != NULL )
                    PmmFixOwnerList( (xmlNodePtr)iterator->properties, parent );
                PmmFixOwnerList(iterator->children, parent);
            }
        }
    }
}

/**
 * this functions fixes the reference counts for an entire subtree.
 * it is very important to fix an entire subtree after node operations
 * where the documents or the owner node may get changed. this method is
 * aware about nodes that already belong to a certain owner node. 
 *
 * the method uses the internal methods PmmFixNode and PmmChildNodes to
 * do the real updates.
 * 
 * in the worst case this traverses the subtree twice durig a node 
 * operation. this case is only given when the node has to be
 * adopted by the document. Since the ownerdocument and the effective 
 * owner may differ this double traversing makes sense.
 */ 
int
PmmFixOwner( ProxyNodePtr nodetofix, ProxyNodePtr parent ) 
{
    ProxyNodePtr oldParent = NULL;

    xs_warn("fix");
    if ( nodetofix != NULL ) {
        if ( PmmNODE(nodetofix)->type != XML_DOCUMENT_NODE ) {
            xs_warn("node is there");

            if ( PmmOWNER(nodetofix) )
                oldParent = PmmOWNERPO(nodetofix);
            
            /* The owner data is only fixed if the node is neither a
             * fragment nor a document. Also no update will happen if
             * the node is already his owner or the owner has not
             * changed during previous operations.
             */
            if( oldParent != parent ) {
                if ( parent && parent != nodetofix ){
                    PmmOWNER(nodetofix) = PmmNODE(parent);
                    PmmREFCNT_inc( parent );
                }
                else {
                    PmmOWNER(nodetofix) = NULL;
                }

                if ( oldParent && oldParent != nodetofix )
                    PmmREFCNT_dec(oldParent);

                if ( PmmNODE(nodetofix)->type != XML_ATTRIBUTE_NODE
                     && PmmNODE(nodetofix)->properties != NULL )
                    PmmFixOwnerList( (xmlNodePtr)PmmNODE(nodetofix)->properties,
                                     parent );
                PmmFixOwnerList(PmmNODE(nodetofix)->children, parent);
            }
            else {
                xs_warn( "node doesn't need to get fixed" );
            }
            return(1);
        }
    }
    return(0);
}

ProxyNodePtr
PmmNewContext(xmlParserCtxtPtr node)
{
    ProxyNodePtr proxy;

    if ( node->_private == NULL ) {
        proxy = (ProxyNodePtr)malloc(sizeof(ProxyNode));
        if (proxy != NULL) {
            proxy->node  = (xmlNodePtr)node;
            proxy->owner   = NULL;
            proxy->count   = 0;
            node->_private = (void*) proxy;
        }
    }
    else {
        proxy = (ProxyNodePtr)node->_private;
    }
    return proxy;
}
 
int
PmmContextREFCNT_dec( ProxyNodePtr node ) 
{ 
    xmlParserCtxtPtr libnode = NULL;
    int retval = 0;
    if ( node ) {
        retval = PmmREFCNT(node)--;
        if ( PmmREFCNT(node) <= 0 ) {
            xs_warn( "NODE DELETATION\n" );
            libnode = (xmlParserCtxtPtr)PmmNODE( node );
            if ( libnode != NULL ) {
                libnode->_private = NULL;
                PmmNODE( node ) = NULL;
                xmlFreeParserCtxt(libnode);
            }
            free( node );
        }
    }
    return retval;
}

SV*
PmmContextSv( xmlParserCtxtPtr ctxt )
{
    ProxyNodePtr dfProxy= NULL;
    SV * retval = &PL_sv_undef;
    const char * CLASS = "XML::LibXML::ParserContext";

    if ( ctxt != NULL ) {
        dfProxy = PmmNewContext(ctxt);

        retval = NEWSV(0,0);
        sv_setref_pv( retval, CLASS, (void*)dfProxy );
        PmmREFCNT_inc(dfProxy);            
    }         
    else {
        xs_warn( "no node found!" );
    }

    return retval;
}

xmlParserCtxtPtr
PmmSvContext( SV * scalar ) 
{
    xmlParserCtxtPtr retval = NULL;

    if ( scalar != NULL
         && scalar != &PL_sv_undef
         && sv_isa( scalar, "XML::LibXML::ParserContext" )
         && SvPROXYNODE(scalar) != NULL  ) {
        retval = (xmlParserCtxtPtr)PmmNODE( SvPROXYNODE(scalar) );
    }
    return retval;
}

/** 
 * encodeString returns an UTF-8 encoded String
 * while the encodig has the name of the encoding of string
 **/ 
xmlChar*
PmmEncodeString( const char *encoding, const xmlChar *string ){
    xmlCharEncoding enc;
    xmlChar *ret = NULL;
    xmlBufferPtr in, out;
    xmlCharEncodingHandlerPtr coder = NULL;
    
    if ( string != NULL ) {
        if( encoding != NULL ) {
            xs_warn( encoding );
            enc = xmlParseCharEncoding( encoding );
            if ( enc > 1 ) {
                coder= xmlGetCharEncodingHandler( enc );
            }
            else if ( enc == 1 ) {
                ret = xmlStrdup( string );
            }
            else if ( enc == XML_CHAR_ENCODING_ERROR ){
                xs_warn("no standard encoding\n");
                coder = xmlFindCharEncodingHandler( encoding );
            }
            else {
                xs_warn("no encoding found\n");
            }

            if ( coder != NULL ) {
                xs_warn("coding machine found\n");
                in    = xmlBufferCreate();
                out   = xmlBufferCreate();
                xmlBufferCCat( in, string );
                if ( xmlCharEncInFunc( coder, out, in ) >= 0 ) {
                    ret = xmlStrdup( out->content );
                }
                else {
                     xs_warn( "b0rked encoiding!\n");
                }
                    
                xmlBufferFree( in );
                xmlBufferFree( out );
            }
            else {
                xs_warn("no coder found\n");
                /* ret = xmlStrdup( string ); */
            }
        }
        else {
            /* if utf-8 is requested we do nothing */
            ret = xmlStrdup( string );
        }
    }
    return ret;
}

/**
 * decodeString returns an $encoding encoded string.
 * while string is an UTF-8 encoded string and 
 * encoding is the coding name
 **/
char*
PmmDecodeString( const char *encoding, const xmlChar *string){
    char *ret=NULL;
    xmlCharEncoding enc;
    xmlBufferPtr in, out;
    xmlCharEncodingHandlerPtr coder = NULL;

    if ( string != NULL ) {
        if( encoding != NULL ) {
            enc = xmlParseCharEncoding( encoding );
            if ( enc > 1 ) {
                coder= xmlGetCharEncodingHandler( enc );
            }
            else if ( enc == 1 ) {
                ret = xmlStrdup( string );
            }
            else if ( enc == XML_CHAR_ENCODING_ERROR ) {
                coder = xmlFindCharEncodingHandler( encoding );
            }
            else {
                xs_warn("no encoding found");
            }

            if ( coder != NULL ) {
                in  = xmlBufferCreate();
                out = xmlBufferCreate();
                    
                xmlBufferCat( in, string );        
                if ( xmlCharEncOutFunc( coder, out, in ) >= 0 ) {
                    ret=xmlStrdup(out->content);
                }
                else {
                    /* printf("decoding error \n"); */
                }
            
                xmlBufferFree( in );
                xmlBufferFree( out );
                xmlCharEncCloseFunc( coder );
            }
        }
        else {
            ret = xmlStrdup(string);
        }
    }
    return ret;
}

SV*
C2Sv( const xmlChar *string, const xmlChar *encoding )
{
    SV *retval = &PL_sv_undef;

    if ( string != NULL ) {
        if ( encoding == NULL || xmlStrcmp( encoding, "UTF8" ) == 0 ) {
            /* create an UTF8 string. */       
            STRLEN len = 0;
            xs_warn("set UTF8 string");
            len = xmlStrlen( string );
            /* create the SV */
            retval = newSVpvn( (const char *)string, len );
#ifdef HAVE_UTF8
            xs_warn("set UTF8-SV-flag");
            SvUTF8_on(retval);
#endif            
        }
        else {
            /* just create an ordinary string. */
            xs_warn("set ordinary string");
            retval = newSVpvn( (const char *)string, xmlStrlen( string ) );
        }
    }

    return retval;
}

xmlChar *
Sv2C( SV* scalar, const xmlChar *encoding )
{
    xmlChar *retval = NULL;
    xs_warn("sv2c start!");
    if ( scalar != NULL && scalar != &PL_sv_undef ) {
        STRLEN len;
        char * t_pv =SvPV(scalar, len);
        xmlChar* string = xmlStrdup((xmlChar*)t_pv);
        /* Safefree( t_pv ); */

        if ( xmlStrlen(string) > 0 ) {
            xmlChar* ts;
            xs_warn( "no undefs" );
#ifdef HAVE_UTF8
            xs_warn( "use UTF8" );
            if( !DO_UTF8(scalar) && encoding != NULL ) {
#else
            if ( encoding != NULL ) {
#endif
                xs_warn( "domEncodeString!" );
                ts= PmmEncodeString( encoding, string );
                xs_warn( "done!" );
                if ( string != NULL ) 
                    xmlFree(string);
                string=ts;
            }
            retval = xmlStrdup(string);
            xmlFree(string);
        }
    }
    xs_warn("sv2c end!");
    return retval;
}


SV*
nodeC2Sv( const xmlChar * string,  xmlNodePtr refnode )
{
    /* this is a little helper function to avoid to much redundand
       code in LibXML.xs */
    SV* retval;

    if ( refnode != NULL ) {
        xmlDocPtr real_doc = refnode->doc;
        if ( real_doc && real_doc->encoding != NULL ) {

            xmlChar * decoded = PmmDecodeString( (const char *)real_doc->encoding ,
                                                 (const xmlChar *)string );

            retval = C2Sv( decoded, real_doc->encoding );
            xmlFree( decoded );
        }
        else {
            retval = C2Sv(string, NULL);
        }
    }
    else {
        retval = C2Sv(string, NULL);
    }

    return retval;
}

xmlChar *
nodeSv2C( SV * scalar, xmlNodePtr refnode )
{
    /* this function requires conditionized compiling, because we
       request a function, that does not exists in earlier versions of
       perl. in this cases the library assumes, all strings are in
       UTF8. if a programmer likes to have the intelligent code, he
       needs to upgrade perl */
#ifdef HAVE_UTF8        
    if ( refnode != NULL ) {
        xmlDocPtr real_dom = refnode->doc;
        xs_warn("have node!");
        if (real_dom != NULL &&real_dom->encoding != NULL ) {
            xs_warn("encode string!");
            return Sv2C(scalar,real_dom->encoding);
        }
    }
    xs_warn("no encoding !!");
#endif

    return  Sv2C( scalar, NULL ); 
}
