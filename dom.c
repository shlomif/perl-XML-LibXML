#include <libxml/tree.h>
#include <libxml/encoding.h>
#include <libxml/xmlmemory.h>
#include <libxml/parser.h>
#include <libxml/xmlIO.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>

xmlDocPtr
domCreateDocument( xmlChar *version, xmlChar *enc ){
  xmlDocPtr doc = 0;
    doc = xmlNewDoc( version );  
    doc->charset  = XML_CHAR_ENCODING_UTF8;
    doc->encoding = xmlStrdup(enc);
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
domAppendChild( xmlNodePtr self,
		xmlNodePtr newChild ){
  /* unbind the new node if nessecary ...  */
  if ( newChild == 0 ){
    return 0;
  }
  if ( self == 0 ) {
    return newChild;
  }

  newChild= domUnbindNode( newChild );
  /* fix the document if they are from different documents 
   * actually this has to be done for ALL nodes in the subtree... 
   **/
  if ( self->doc != newChild->doc ) {
    newChild->doc = self->doc;
  }
  
  if ( self->children != 0 ) {
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
  if ( new == 0 ) {
    return old;
  }
  if ( self== 0 ){
    return 0;
  }
  if ( old == 0 ) {
    domAppendChild( self, new );
    return old;
  }
  if ( old->parent != self ) {
    /* should not do this!!! */
    return new;
  }
  new = domUnbindNode( new ) ;
  new->parent = self;
  
  /* this piece is quite important */
  if ( new->doc != self->doc ) {
    new->doc = self->doc;
  }

  if ( old->next != 0 ) 
    old->next->prev = new;
  if ( old->prev != 0 ) 
    old->prev->next = new;
  
  new->next = old->next;
  new->prev = old->prev;
  
  if ( old == self->children )
    self->children = new;
  if ( old == self->last )
    self->last = new;
  
  old->parent = 0;
  old->next   = 0;
  old->prev   = 0;
 
  return old;
}

xmlNodePtr
domRemoveNode( xmlNodePtr self, xmlNodePtr old ) {
  if ( (self != 0)  && (old!=0) && (self == old->parent ) ) {
    domUnbindNode( old );
  }
  return old ;
}

void
domSetNodeValue( xmlNodePtr n , xmlChar* val ){
  if ( n == 0 ) 
    return;
  if( n->content != 0 ) {
    xmlFree( n->content );
  }
  n->content = xmlStrdup( val );
}


void
domSetParentNode( xmlNodePtr self, xmlNodePtr p ) {
  if( self != 0 ){
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
  if ( (self != 0) && (self->parent != 0) ) { 
    if ( self->next != 0 )
      self->next->prev = self->prev;
    if ( self->prev != 0 )
      self->prev->next = self->next;
    if ( self == self->parent->last ) 
      self->parent->last = self->prev;
    if ( self == self->parent->children ) 
      self->parent->children = self->next;
    
    self->parent = 0;
    self->next   = 0;
    self->prev   = 0;
  }

  return self;
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

  if ( elem != 0 ) {
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
  xmlNodePtr elem = 0;

  if ( ( self != 0 ) && ( strNodeContent != 0 ) ) {
    elem = xmlNewCDataBlock( self, strNodeContent, xmlStrlen(strNodeContent) );
    elem->next = 0;
    elem->prev = 0;
    elem->children = 0 ;
    elem->last = 0;
    elem->doc = self->doc;   
  }

  return elem;
}


xmlNodePtr 
domDocumentElement( xmlDocPtr doc ) {
  xmlNodePtr cld=0;
  if ( doc != 0 && doc->doc != 0 && doc->doc->children != 0 ) {
    cld= doc->doc->children;
    while ( cld != 0 && cld->type != XML_ELEMENT_NODE ) 
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



xmlNodeSetPtr
domGetElementsByTagName( xmlNodePtr n, xmlChar* name ){
  xmlNodeSetPtr rv = 0;
  xmlNodePtr cld = 0;

  if ( n != 0 && name != 0 ) {
    cld = n->children;
    while ( cld ) {
      if ( xmlStrcmp( name, cld->name ) == 0 ){
	if ( rv == 0 ) {
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
