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

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <libxml/parser.h>

#include "dom.h"

#ifdef __cplusplus
}
#endif

#ifdef XS_WARNINGS
#define xs_warn(string) warn(string) 
#else
#define xs_warn(string)
#endif

struct _ProxyObject {
    void * object;
    SV * extra;
};

typedef struct _ProxyObject ProxyObject;

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
            retval = newSVpvn( (char *)xmlStrdup(string), len );
#ifdef HAVE_UTF8
            xs_warn("set UTF8-SV-flag");
            SvUTF8_on(retval);
#endif            
        }
        else {
            /* just create an ordinary string. */
            xs_warn("set ordinary string");
            retval = newSVpvn( (char *)xmlStrdup(string), xmlStrlen( string ) );
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
        xmlChar* string = xmlStrdup((xmlChar*)SvPV(scalar, len));
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
                ts= domEncodeString( encoding, string );
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
        xmlDocPtr real_dom = refnode->doc;
        if ( real_dom->encoding != NULL ) {

            xmlChar * decoded = domDecodeString( (const char *)real_dom->encoding ,
                                                 (const xmlChar *)string );

            retval = C2Sv( decoded, real_dom->encoding );
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

        if (real_dom != NULL && real_dom->encoding != NULL
             && !DO_UTF8(scalar) ) {
            xs_warn("encode string!");
            return Sv2C(scalar,real_dom->encoding);
        }
    }
    xs_warn("no encoding !!");
#endif

    return  Sv2C( scalar, NULL ); 
}

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
free_proxy_node ( SV* nodesv )
{
    ProxyObject * p;
    p = (ProxyObject*)SvIV((SV*)SvRV(nodesv));
    if ( p != NULL ) {
        p->object = NULL;
        if ( p->extra != NULL ) {
            /* in this case the owner SV needs to be decreased */
            
        }
        p->extra = NULL;
        Safefree( p );
    }
}

SV*
nodeToSv( xmlNodePtr node ) 
{
    ProxyObject * dfProxy= NULL;
    SV * retval = &PL_sv_undef;
    const char * CLASS = "XML::LibXML::Node";
    
    if ( node != NULL ) {
        /* find out about the class */
        CLASS = domNodeTypeName(node);

        dfProxy = make_proxy_node(node);
        retval = NEWSV(0,0);
        sv_setref_pv( retval, (char*)CLASS, (void*)dfProxy );
    }

    return retval;
}

xmlNodePtr
getSvNode( SV* perlnode ) 
{
    xmlNodePtr retval = NULL;

    if ( perlnode != NULL && perlnode != &PL_sv_undef ) {
        retval = (xmlNodePtr)((ProxyObject*)SvIV((SV*)SvRV(perlnode)))->object;
    }
    return retval;
}


SV*
getSvNodeExtra( SV* perlnode ) 
{
    SV * retval = NULL;
    if ( perlnode != NULL && perlnode != &PL_sv_undef ) {
        retval = (SV*)((ProxyObject*)SvIV((SV*)SvRV(perlnode)))->extra;
    }
    return retval;
}

SV* 
setSvNodeExtra( SV* perlnode, SV* extra )
{
    if ( perlnode != NULL && perlnode != &PL_sv_undef ) {
        (SV*)((ProxyObject*)SvIV((SV*)SvRV(perlnode)))->extra = extra;
        if ( perlnode != extra ) { /* different objects */
           SvREFCNT_inc(extra);
        }
    }
    return perlnode;
}

void
fix_proxy_extra( SV* nodetofix, SV* parent ) 
{
    SV * oldParent = NULL;
    xs_warn("fix");
    if ( nodetofix != NULL
         && nodetofix != &PL_sv_undef ) {
        xs_warn("node is there");
        /* this following condition will be removed w/ the new MM */
        if ( parent != NULL && parent != &PL_sv_undef ) {
            xs_warn("parent is there, too");
            /* we are paranoid about circular references! */
            /* and test if we from within deal with the same dom. */
            oldParent = getSvNodeExtra(nodetofix);
            
            /* check if our node is a document or a fragment!!!! */
            if ( getSvNode(nodetofix)->type != XML_DOCUMENT_FRAG_NODE
                 && getSvNode(nodetofix)->type != XML_DOCUMENT_NODE
                 && getSvNode(nodetofix) != getSvNode(parent)
                 && getSvNode(oldParent) !=  getSvNode(parent) ) {

                /* if we deal with different DOM's we need to update
                 * the extra entry
                 */ 
                xs_warn("ok, switch parents");

                /* new MM needs to test if the node is still w/ in the 
                 * same subtree in this case.
                 */

                setSvNodeExtra(nodetofix, parent);

                /* decrease the old parent and increase the new parent */
                if ( oldParent != NULL && oldParent != &PL_sv_undef ) {
                    SvREFCNT_dec(oldParent);
                }
                
                if ( parent != NULL && parent != &PL_sv_undef ) {
                    xs_warn("increase parent!");
                    SvREFCNT_inc(parent);
                }                    
            } /* otherwise there is nothing to do */
            else {
                xs_warn("illegal node to fix!");
            }
        }
    }
}
