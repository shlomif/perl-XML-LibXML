#include <libxml/tree.h>
#include <libxml/encoding.h>
#include <libxml/xmlmemory.h>
#include <libxml/parser.h>
#include <libxml/xmlIO.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>

xmlDocPtr
domCreateDocument( xmlChar *version, xmlChar *enc ){
    xmlDocPtr doc = NULL;
    doc = xmlNewDoc( version );  
    doc->charset  = XML_CHAR_ENCODING_UTF8;
    if ( enc != NULL && *enc!= 0 ) {
      /* if an encoding is passed, we will assume UTF8, otherwise we set 
       * the passed encoding 
       */
        doc->encoding = xmlStrdup(enc);
    }
    else {
        doc->encoding = xmlStrdup("UTF-8");
    }

    return doc;
}

/* this function is pretty neat, since you can read in well balanced 
 * strings and get a list of nodes, which can be added to any other node.
 *
 * the code is pretty heavy i think, but deep in my heard i believe it's 
 * worth it :) (e.g. if you like to read a chunk of well-balanced code 
 * from a databasefield)
 *
 * in 99% i believe it is faster to create the dom by hand, and skip the 
 * parsing job which has to be done here.
 */
xmlNodePtr 
domReadWellBalancedString( xmlDocPtr doc, xmlChar* block ) {
  int retCode       = -1;
  xmlNodePtr helper = NULL;
  xmlNodePtr nodes  = NULL;
  
  if ( doc && block ) {
    /* read and encode the chunk */
    retCode = xmlParseBalancedChunkMemory( doc, 
                                           NULL,
                                           NULL,
                                           0,
                                           block,
                                           &nodes );
    
    /* error handling */
    if ( retCode != 0 ) {
      /* if the code was not well balanced, we will not return 
       * a bad node list, but we have to free the nodes */
      while( nodes != NULL ) {
        helper = nodes->next;
        xmlFreeNode( nodes );
        nodes = helper;
      }
    }
  }

  return nodes;
}

xmlNodePtr
domUnbindNode( xmlNodePtr );

xmlNodePtr
domIsNotParentOf( xmlNodePtr node1, xmlNodePtr node2 );

xmlNodePtr
domImportNode( xmlDocPtr doc, xmlNodePtr node, int move );

xmlNodePtr
domRemoveChild( xmlNodePtr self, xmlNodePtr old );

/**
 * Name: domName
 * Synopsis: string = domName( node );
 *
 * domName returns the full name for the current node.
 * If the node belongs to a namespace it returns the prefix and 
 * the local name. otherwise only the local name is returned.
 **/
const xmlChar*
domName(xmlNodePtr node) {
  xmlChar *qname = NULL; 
  if ( node ) {
    if (node->ns != NULL) {
      if (node->ns->prefix != NULL) {
        qname = xmlStrdup( node->ns->prefix );
        qname = xmlStrcat( qname , ":" );
        qname = xmlStrcat( qname , node->name );
      } 
      else {
        qname = xmlStrdup( node->name );
      }
    } 
    else {
      qname = xmlStrdup( node->name );
    }
  }
  return qname;
}

void
domSetName( xmlNodePtr node, xmlChar* name ) {
  /* TODO: add ns support */
  if ( node == NULL || name == NULL ) 
    return ;
  if ( node->name != NULL ) {
    /* required since node->name is const! */
    xmlFree( (void*) node->name );
  }
  node->name = xmlStrdup( name );
}

xmlNodePtr
domAppendChild( xmlNodePtr self,
		xmlNodePtr newChild ){
  /* unbind the new node if nessecary ...  */

  newChild = domIsNotParentOf( newChild, self );
  if ( newChild == NULL ){
    return NULL;
  }
  if ( self == NULL ) {
    return newChild;
  }


  if ( newChild->doc == self->doc ){
    newChild= domUnbindNode( newChild );
  }
  else {
    newChild= domImportNode( self->doc, newChild, 1 );
  }

  /* fix the document if they are from different documents 
   * actually this has to be done for ALL nodes in the subtree... 
   **/
  if ( self->doc != newChild->doc ) {
    newChild->doc = self->doc;
  }
  
  if ( self->children != NULL ) {
    if ( newChild->type   == XML_TEXT_NODE && 
	 self->last->type == XML_TEXT_NODE ) {
      int len = xmlStrlen(newChild->content);
      xmlNodeAddContentLen(self->last, newChild->content, len);
      xmlFreeNode( newChild );
      return self->last;
    }
    else {
      self->last->next = newChild;
      newChild->prev = self->last;
      self->last = newChild;
      newChild->parent= self;
    }
  }
  else {
    self->children = newChild;
    self->last     = newChild;
    newChild->parent= self;
  }
  return newChild;
}

xmlNodePtr
domReplaceChild( xmlNodePtr self, xmlNodePtr new, xmlNodePtr old ) {
  new = domIsNotParentOf( new, self );
  if ( new == NULL ) {
    /* level2 sais nothing about this case :( */
    return domRemoveChild( self, old );
  }

  if ( self== NULL ){
    return NULL;
  }

  if ( new == old ) {
    /* dom level 2 throw no exception if new and old are equal */ 
    return new;
  }

  if ( old == NULL ) {
    domAppendChild( self, new );
    return old;
  }
  if ( old->parent != self ) {
    /* should not do this!!! */
    return new;
  }

  if ( new->doc == self->doc ) {
    new = domUnbindNode( new ) ;
  }
  else {
    new = domImportNode( self->doc, new, 1 );
  }
  new->parent = self;
  
  /* this piece is quite important */
  if ( new->doc != self->doc ) {
    new->doc = self->doc;
  }

  if ( old->next != NULL ) 
    old->next->prev = new;
  if ( old->prev != NULL ) 
    old->prev->next = new;
  
  new->next = old->next;
  new->prev = old->prev;
  
  if ( old == self->children )
    self->children = new;
  if ( old == self->last )
    self->last = new;
  
  old->parent = NULL;
  old->next   = NULL;
  old->prev   = NULL;
 
  return old;
}

xmlNodePtr
domRemoveChild( xmlNodePtr self, xmlNodePtr old ) {
  if ( (self != NULL)  && (old!=NULL) && (self == old->parent ) ) {
    domUnbindNode( old );
  }
  return old ;
}

xmlNodePtr
domInsertBefore( xmlNodePtr self, 
                 xmlNodePtr newChild,
                 xmlNodePtr refChild ){

  if ( self == NULL ) {
    return NULL;
  }

  newChild = domIsNotParentOf( newChild, self );

  if ( refChild == newChild ) {
    return newChild;
  }

  if ( refChild == NULL && newChild != NULL ) {
    /* insert newChild as first Child */
    if ( self->children == NULL ) {
      return domAppendChild( self, newChild );
    }
    
    if ( self->doc == newChild->doc ){
      newChild = domUnbindNode( newChild );
    }
    else {
      newChild = domImportNode( self->doc, newChild, 1 );
    }

    newChild->next = self->children;
    self->children->prev = newChild;
   
    self->children = newChild;

    return newChild;
  }

  if ( newChild != NULL && 
       self == refChild->parent ) {
    /* find the refchild, to avoid spoofed parents */
    xmlNodePtr hn = self->children;
    while ( hn ) {
      if ( hn == refChild ) {
        /* found refChild */
        if ( self->doc == newChild->doc ){
          newChild = domUnbindNode( newChild );
        }
        else {
          newChild = domImportNode( self->doc, newChild, 1 );
        }

        newChild->parent = self;
        newChild->next = refChild;
        newChild->prev = refChild->prev;
        if ( refChild->prev != NULL ) {
          refChild->prev->next = newChild;
        }
        refChild->prev = newChild;
        if ( refChild == self->children ) {
          self->children = newChild;
        }
        return newChild;
      }
      hn = hn->next;
    }
  }
  return NULL;
}

xmlNodePtr
domInsertAfter( xmlNodePtr self, 
                xmlNodePtr newChild,
                xmlNodePtr refChild ){
  if ( self == NULL ) {
    return NULL;
  }

  newChild = domIsNotParentOf( newChild, self );

  if ( refChild == newChild ) {
    return newChild;
  }

  if ( refChild == NULL ) {
    return domAppendChild( self, newChild );
  }

  if ( newChild != NULL && 
       self == refChild->parent &&
       refChild != newChild ) {
    /* find the refchild, to avoid spoofed parents */
    xmlNodePtr hn = self->children;
    while ( hn ) {
      if ( hn == refChild ) {
        /* found refChild */
        if ( self->doc == newChild->doc ) {
          newChild = domUnbindNode( newChild );
        }
        else {
          newChild = domImportNode( self->doc , newChild, 1 );
        }

        newChild->parent = self;
        newChild->prev = refChild;
        newChild->next = refChild->next;
        if ( refChild->next != NULL ) {
          refChild->next->prev = newChild;
        }
        refChild->next = newChild;

        if ( refChild == self->last ) {
          self->last = newChild;
        }
        return newChild;
      }
      hn = hn->next;
    }
  }
  return NULL;
}

void
domSetNodeValue( xmlNodePtr n , xmlChar* val ){
  xmlDocPtr doc = NULL;
  
  if ( n == NULL ) 
    return;

  if( n->content != NULL ) {
    /* free old content */
    xmlFree( n->content );
  }

  doc = n->doc;

  if ( doc != NULL ) {
    xmlCharEncodingHandlerPtr handler = xmlGetCharEncodingHandler( xmlParseCharEncoding(doc->encoding) );

    if ( handler != NULL ){
       xmlBufferPtr in  = xmlBufferCreate();
       xmlBufferPtr out = xmlBufferCreate();   
       int len=-1;

       xmlBufferCat( in, val );
       len = xmlCharEncInFunc( handler, out, in );

       if ( len >= 0 ) {
         n->content = xmlStrdup( out->content );
       }
       else {
         printf( "\nencoding error %d \n", len );
         n->content = xmlStrdup( "" );
       }
    }
    else {
      /* handler error => no output */ 
      n->content = xmlStrdup( "" );
    }
  }
  else {    
    /* take data as UTF-8 */
    n->content = xmlStrdup( val );
  }
}


void
domSetParentNode( xmlNodePtr self, xmlNodePtr p ) {
  /* never set the parent to a node in the own subtree */ 
  self = domIsNotParentOf( self, p );
  if( self != NULL ){
    if( self->parent != p ){
      domUnbindNode( self );
      self->parent = p;
      if( p->doc != self->doc ) {
	self->doc = p->doc;
      }
    }
  }
}

xmlNodePtr
domUnbindNode( xmlNodePtr self ) {
  if ( (self != NULL) && (self->parent != NULL) ) { 
    if ( self->next != NULL )
      self->next->prev = self->prev;
    if ( self->prev != NULL )
      self->prev->next = self->next;
    if ( self == self->parent->last ) 
      self->parent->last = self->prev;
    if ( self == self->parent->children ) 
      self->parent->children = self->next;

    self->parent = NULL;
    self->next   = NULL;
    self->prev   = NULL;
  }
  return self;
}

/**
 * donIsNotParentOf tests, if node1 is parent of node2. this test is very
 * important to avoid circular constructs in trees. if node1 is NOT parent
 * of node2 the function returns node1, otherwise NULL.
 **/
xmlNodePtr
domIsNotParentOf( xmlNodePtr node1, xmlNodePtr node2 ) {
  xmlNodePtr helper = NULL;

  if ( node1 == NULL ) {
    return NULL;
  }

  if( node2 == NULL || node1->doc != node2->doc) {
    return node1;
  }
  
  helper= node2;
  while ( helper!=NULL ) {
    if( helper == node1 ) {
      return NULL;
    }
    
    helper = helper->parent;
    if ( (xmlDocPtr) helper == node2->doc ) {
      helper = NULL;
    }
  }

  return node1;
}

/**
 * this is a wrapper function that does the type evaluation for the 
 * node. this makes the code a little more readable in the .XS
 * 
 * the code is not really portable, but i think we'll avoid some 
 * memory leak problems that way.
 **/

const char*
domNodeTypeName( xmlNodePtr elem ){
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
    default:
      name = "XML::LibXML::Node";
      break;
    };
    return name;
  }

  return "";
}

xmlNodePtr
domCreateCDATASection( xmlDocPtr self , xmlChar * strNodeContent ){
  xmlNodePtr elem = NULL;

  if ( ( self != NULL ) && ( strNodeContent != NULL ) ) {
    elem = xmlNewCDataBlock( self, strNodeContent, xmlStrlen(strNodeContent) );
    elem->next = NULL;
    elem->prev = NULL;
    elem->children = NULL ;
    elem->last = NULL;
    elem->doc = self->doc;   
  }

  return elem;
}


xmlNodePtr 
domDocumentElement( xmlDocPtr doc ) {
  xmlNodePtr cld=NULL;
  if ( doc != NULL && doc->doc != NULL && doc->doc->children != NULL ) {
    cld= doc->doc->children;
    while ( cld != NULL && cld->type != XML_ELEMENT_NODE ) 
      cld= cld->next;
  
  }
  return cld;
}

/**
 * setDocumentElement:
 * @doc: the document
 * @newRoot: the new rootnode
 *
 * a document can have only ONE root node, so this function searches
 * the first element and relaces this element with newRoot.
 * 
 * Returns the old root node.
 **/
xmlNodePtr
domSetDocumentElement( xmlDocPtr doc, xmlNodePtr newRoot ) { 
  return domReplaceChild( (xmlNodePtr)doc->doc, 
			  newRoot, 
			  domDocumentElement( doc )) ;
}


xmlNodePtr
domSetOwnerDocument( xmlNodePtr self, xmlDocPtr newDoc );

xmlNodePtr
domImportNode( xmlDocPtr doc, xmlNodePtr node, int move ) {
  xmlNodePtr return_node = node;

  if ( !doc ) {
    return_node = node;
  }
  else if ( node && node->doc != doc ) {
    if ( move ) {
      return_node = domUnbindNode( node );
    }
    else {
      return_node = xmlCopyNode( node, 1 );
    }
    /* tell all children about the new boss */ 
    return_node = domSetOwnerDocument( return_node, doc ); 
  }
 
  return return_node;
}

xmlNodeSetPtr
domGetElementsByTagName( xmlNodePtr n, xmlChar* name ){
  xmlNodeSetPtr rv = NULL;
  xmlNodePtr cld = NULL;

  if ( n != NULL && name != NULL ) {
    cld = n->children;
    while ( cld != NULL ) {
      if ( xmlStrcmp( name, cld->name ) == 0 ){
        if ( rv == NULL ) {
          rv = xmlXPathNodeSetCreate( cld ) ;
        }
        else {
          xmlXPathNodeSetAdd( rv, cld );
        }
      }
      cld = cld->next;
    }
  }
  
  return rv;
}


xmlNodeSetPtr
domGetElementsByTagNameNS( xmlNodePtr n, xmlChar* nsURI, xmlChar* name ){
  xmlNodeSetPtr rv = NULL;

  if ( nsURI == NULL ) {
    return domGetElementsByTagName( n, name );
  }
  
  if ( n != NULL && name != NULL  ) {
    xmlNodePtr cld = n->children;
    while ( cld != NULL ) {
      if ( xmlStrcmp( name, cld->name ) == 0 
           && cld->ns != NULL
           && xmlStrcmp( nsURI, cld->ns->href ) == 0  ){
        if ( rv == NULL ) {
          rv = xmlXPathNodeSetCreate( cld ) ;
        }
        else {
          xmlXPathNodeSetAdd( rv, cld );
        }
      }
      cld = cld->next;
    }
  }
  
  return rv;
}

xmlNodePtr
domSetOwnerDocument( xmlNodePtr self, xmlDocPtr newDoc ) {
    if ( newDoc == NULL ) {
        return NULL;
    }

    if ( self != NULL ) {
        xmlNodePtr pNode = self->children;

        self->doc = newDoc;
        while ( pNode != NULL ) {
            domSetOwnerDocument( pNode, newDoc );
            pNode = pNode->next;
        }
    }

    return self;
}

xmlNsPtr
domNewNs ( xmlNodePtr elem , xmlChar *prefix, xmlChar *href ) {
  xmlNsPtr ns = NULL;
  
  if (elem != NULL) {
    ns = xmlSearchNs( elem->doc, elem, prefix );
  }
  /* prefix is not in use */
  if (ns == NULL) {
    ns = xmlNewNs( elem , href , prefix );
    ns->next = NULL;
  } else {
    /* prefix is in use; if it has same URI, let it go, otherwise it's
       an error */
    if (!xmlStrEqual(href, ns->href)) {
      ns = NULL;
    }
  }
  return ns;
}

/* This routine may or may not make it into libxml2; Matt wanted it in
   here to be nice to those with older libxml2 installations.
   This instance is renamed from xmlHasNsProp to domHasNsProp. */
/**
 * xmlHasNsProp:
 * @node:  the node
 * @name:  the attribute name
 * @namespace:  the URI of the namespace
 *
 * Search for an attribute associated to a node
 * This attribute has to be anchored in the namespace specified.
 * This does the entity substitution.
 * This function looks in DTD attribute declaration for #FIXED or
 * default declaration values unless DTD use has been turned off.
 *
 * Returns the attribute or the attribute declaration or NULL
 *     if neither was found.
 */
xmlAttrPtr
domHasNsProp(xmlNodePtr node, const xmlChar *name, const xmlChar *namespace) {
  xmlAttrPtr prop;
  xmlDocPtr doc;
  xmlNsPtr ns;
  
  if (node == NULL)
 	return(NULL);
  
  prop = node->properties;
  if (namespace == NULL)
    return(xmlHasProp(node, name));
  while (prop != NULL) {
    /*
     * One need to have
     *   - same attribute names
     *   - and the attribute carrying that namespace
 	 *         or
     
     SJT: This following condition is wrong IMHO; I reported it as a bug on libxml2
     
	 *         no namespace on the attribute and the element carrying it
	 */
    if ((xmlStrEqual(prop->name, name)) &&
        (/* ((prop->ns == NULL) && (node->ns != NULL) &&
            (xmlStrEqual(node->ns->href, namespace))) || */
         ((prop->ns != NULL) &&
          (xmlStrEqual(prop->ns->href, namespace))))) {
      return(prop);
    }
    prop = prop->next;
  }
  
#if 0
  /* xmlCheckDTD is static in libxml/tree.c; it is set there to 1
     and never changed, so commenting this out doesn't change the
     behaviour */
  if (!xmlCheckDTD) return(NULL);
#endif
  
  /*
   * Check if there is a default declaration in the internal
   * or external subsets
   */
  doc =  node->doc;
  if (doc != NULL) {
    if (doc->intSubset != NULL) {
      xmlAttributePtr attrDecl;
      
      attrDecl = xmlGetDtdAttrDesc(doc->intSubset, node->name, name);
      if ((attrDecl == NULL) && (doc->extSubset != NULL))
        attrDecl = xmlGetDtdAttrDesc(doc->extSubset, node->name, name);
      
      if ((attrDecl != NULL) && (attrDecl->prefix != NULL)) {
        /*
         * The DTD declaration only allows a prefix search
         */
        ns = xmlSearchNs(doc, node, attrDecl->prefix);
        if ((ns != NULL) && (xmlStrEqual(ns->href, namespace)))
          return((xmlAttrPtr) attrDecl);
      }
    }
  }
  return(NULL);
}
