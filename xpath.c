#include <libxml/tree.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>

#include "dom.h"

/**
 * Most of the code is stolen from textXPath. 
 * The almost only thing I added, is the storeing of the data, so
 * we can access the data easily - or say more easiely than through
 * libxml2.
 **/

xmlXPathObjectPtr
domXPathFind( xmlNodePtr refNode, xmlChar * path ) {
    xmlNodeSetPtr rv ;
    xmlXPathObjectPtr res = NULL;
  
    rv = xmlXPathNodeSetCreate( 0 );
  
    if ( refNode != NULL && refNode->doc != NULL && path != NULL ) {
        /* we can only do a path in a valid document! 
         */
        xmlXPathContextPtr ctxt;
        xmlXPathCompExprPtr comp;
    
        /* prepare the xpath context */
        ctxt = xmlXPathNewContext( refNode->doc );
        ctxt->node = refNode;
    
        comp = xmlXPathCompile( path );
        if (comp != NULL) {
            res = xmlXPathCompiledEval(comp, ctxt);
            xmlXPathFreeCompExpr(comp);
        }
        
        xmlXPathFreeContext(ctxt);
    }
    return res;
}

xmlNodeSetPtr
domXPathSelect( xmlNodePtr refNode, xmlChar * path ) {
    xmlNodeSetPtr rv ;
    xmlXPathObjectPtr res;
  
    rv = xmlXPathNodeSetCreate( 0 );
    
    res = domXPathFind( refNode, path );
    
    if (res != NULL) {
            /* here we have to transfer the result from the internal
               structure to the return value */
        	/* get the result from the query */
        	/* we have to unbind the nodelist, so free object can 
        	   not kill it */
        rv = res->nodesetval;  
        res->nodesetval = 0 ;
    
    }

    xmlXPathFreeObject(res);

    return rv;
}
