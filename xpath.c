#include <libxml/tree.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>
#include <libxml/uri.h>

#include "dom.h"

void
perlDocumentFunction(xmlXPathParserContextPtr ctxt, int nargs){
    xmlXPathObjectPtr obj, obj2 = NULL;
    xmlChar *base = NULL, *URI;


    if ((nargs < 1) || (nargs > 2)) {
        ctxt->error = XPATH_INVALID_ARITY;
        return;
    }
    if (ctxt->value == NULL) {
        ctxt->error = XPATH_INVALID_TYPE;
        return;
    }

    if (nargs == 2) {
        if (ctxt->value->type != XPATH_NODESET) {
            ctxt->error = XPATH_INVALID_TYPE;
            return;
        }

        obj2 = valuePop(ctxt);
    }

    if (ctxt->value->type == XPATH_NODESET) {
        int i;
        xmlXPathObjectPtr newobj, ret;

        obj = valuePop(ctxt);
        ret = xmlXPathNewNodeSet(NULL);

        if (obj->nodesetval) {
            for (i = 0; i < obj->nodesetval->nodeNr; i++) {
                valuePush(ctxt,
                          xmlXPathNewNodeSet(obj->nodesetval->nodeTab[i]));
                xmlXPathStringFunction(ctxt, 1);
                if (nargs == 2) {
                    valuePush(ctxt, xmlXPathObjectCopy(obj2));
                } else {
                    valuePush(ctxt,
                              xmlXPathNewNodeSet(obj->nodesetval->nodeTab[i]));
                }
                perlDocumentFunction(ctxt, 2);
                newobj = valuePop(ctxt);
                ret->nodesetval = xmlXPathNodeSetMerge(ret->nodesetval,
                                                       newobj->nodesetval);
                xmlXPathFreeObject(newobj);
            }
        }

        xmlXPathFreeObject(obj);
        if (obj2 != NULL)
            xmlXPathFreeObject(obj2);
        valuePush(ctxt, ret);
        return;
    }
    /*
     * Make sure it's converted to a string
     */
    xmlXPathStringFunction(ctxt, 1);
    if (ctxt->value->type != XPATH_STRING) {
        ctxt->error = XPATH_INVALID_TYPE;
        if (obj2 != NULL)
            xmlXPathFreeObject(obj2);
        return;
    }
    obj = valuePop(ctxt);
    if (obj->stringval == NULL) {
        valuePush(ctxt, xmlXPathNewNodeSet(NULL));
    } else {
        if ((obj2 != NULL) && (obj2->nodesetval != NULL) &&
            (obj2->nodesetval->nodeNr > 0)) {
            xmlNodePtr target;

            target = obj2->nodesetval->nodeTab[0];
            if (target->type == XML_ATTRIBUTE_NODE) {
                target = ((xmlAttrPtr) target)->parent;
            }
            base = xmlNodeGetBase(target->doc, target);
        } else {
            base = xmlNodeGetBase(ctxt->context->node->doc, ctxt->context->node);
        }
        URI = xmlBuildURI(obj->stringval, base);
        if (base != NULL)
            xmlFree(base);
        if (URI == NULL) {
            valuePush(ctxt, xmlXPathNewNodeSet(NULL));
        } else {
            if (xmlStrEqual(ctxt->context->node->doc->URL, URI)) {
                valuePush(ctxt, xmlXPathNewNodeSet((xmlNodePtr)ctxt->context->node->doc));
            }
            else {
                xmlDocPtr doc;
                doc = xmlParseFile((const char *)URI);
                if (doc == NULL)
                    valuePush(ctxt, xmlXPathNewNodeSet(NULL));
                else {
                    /* TODO: use XPointer of HTML location for fragment ID */
                    /* pbm #xxx can lead to location sets, not nodesets :-) */
                    valuePush(ctxt, xmlXPathNewNodeSet((xmlNodePtr) doc));
                }
            }
            xmlFree(URI);
        }
    }
    xmlXPathFreeObject(obj);
    if (obj2 != NULL)
        xmlXPathFreeObject(obj2);
}


/**
 * Most of the code is stolen from testXPath. 
 * The almost only thing I added, is the storeing of the data, so
 * we can access the data easily - or say more easiely than through
 * libxml2.
 **/

xmlXPathObjectPtr
domXPathFind( xmlNodePtr refNode, xmlChar * path ) {
    xmlNodeSetPtr rv ;
    xmlXPathObjectPtr res = NULL;
    void * xslt_lib;
    char * error;
  
    rv = xmlXPathNodeSetCreate( 0 );
  
    if ( refNode != NULL && refNode->doc != NULL && path != NULL ) {
        /* we can only do a path in a valid document! 
         */
        xmlXPathContextPtr ctxt;
        xmlXPathCompExprPtr comp;
    
        /* prepare the xpath context */
        ctxt = xmlXPathNewContext( refNode->doc );
        ctxt->node = refNode;
    
        /* get the namespace information */
        if (refNode->type == XML_DOCUMENT_NODE) {
            ctxt->namespaces = xmlGetNsList(refNode->doc, refNode->children);
        }
        else {
            ctxt->namespaces = xmlGetNsList(refNode->doc, refNode);
        }
        ctxt->nsNr = 0;
        if (ctxt->namespaces != NULL) {
            while (ctxt->namespaces[ctxt->nsNr] != NULL)
            ctxt->nsNr++;
        }

        xmlXPathRegisterFunc(ctxt, (const xmlChar *) "document",
            perlDocumentFunction);

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
