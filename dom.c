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
  if ( n == NULL ) 
    return;
  if( n->content != NULL ) {
    xmlFree( n->content );
  }
  n->content = xmlStrdup( val );
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
  xmlNodePtr return_node;

  if ( !doc ) {
    return node;
  }

  if ( node && node->doc != doc ) {
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
    while ( cld ) {
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
