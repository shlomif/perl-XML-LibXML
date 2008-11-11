#ifndef __LIBXML_XPATH_H__
#define __LIBXML_XPATH_H__

#include <libxml/tree.h>
#include <libxml/xpath.h>

void
perlDocumentFunction( xmlXPathParserContextPtr ctxt, int nargs );

xmlNodeSetPtr
domXPathSelect( xmlNodePtr refNode, xmlChar * xpathstring );

xmlXPathObjectPtr
domXPathFind( xmlNodePtr refNode, xmlChar * xpathstring, int to_bool );

xmlNodeSetPtr
domXPathCompSelect( xmlNodePtr refNode, xmlXPathCompExprPtr comp );

xmlXPathObjectPtr
domXPathCompFind( xmlNodePtr refNode, xmlXPathCompExprPtr comp, int to_bool );

xmlNodeSetPtr
domXPathSelectCtxt( xmlXPathContextPtr ctxt, xmlChar * xpathstring );

xmlXPathObjectPtr
domXPathFindCtxt( xmlXPathContextPtr ctxt, xmlChar * xpathstring, int to_bool );

xmlXPathObjectPtr
domXPathCompFindCtxt( xmlXPathContextPtr ctxt, xmlXPathCompExprPtr comp, int to_bool );

#endif
