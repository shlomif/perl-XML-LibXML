/* $Id$ */
#include <libxml/tree.h>
#include <libxml/encoding.h>
#include <libxml/xmlmemory.h>
#include <libxml/parser.h>
#include <libxml/xmlIO.h>
#include <libxml/xpath.h>
#include <libxml/xpathInternals.h>

#include <stdio.h>

#define warn(string) fprintf(stderr, string) 

#ifdef XS_WARNINGS
#define xs_warn(string) fprintf(stderr, string) 
#else
#define xs_warn(string)
#endif

/**
 * Name: domReadWellBalancedString
 * Synopsis: xmlNodePtr domReadWellBalancedString( xmlDocPtr doc, xmlChar *string )
 * @doc: the document, the string should belong to
 * @string: the string to parse
 *
 * this function is pretty neat, since you can read in well balanced 
 * strings and get a list of nodes, which can be added to any other node.
 * (shure - this should return a doucment_fragment, but still it doesn't)
 *
 * the code is pretty heavy i think, but deep in my heard i believe it's 
 * worth it :) (e.g. if you like to read a chunk of well-balanced code 
 * from a databasefield)
 *
 * in 99% the cases i believe it is faster than to create the dom by hand,
 * and skip the parsing job which has to be done here.
 *
 * the repair flag will not be recognized with the current libxml2
 **/
xmlNodePtr 
domReadWellBalancedString( xmlDocPtr doc, xmlChar* block, int repair ) {
    int retCode       = -1;
    xmlNodePtr nodes  = NULL;
    
    if ( block ) {
        /* read and encode the chunk */
        retCode = xmlParseBalancedChunkMemory( doc, 
                                               NULL,
                                               NULL,
                                               0,
                                               block,
                                               &nodes );

/*         retCode = xmlParseBalancedChunkMemoryRecover( doc,  */
/*                                                       NULL, */
/*                                                       NULL, */
/*                                                       0, */
/*                                                       block, */
/*                                                       &nodes, */
/*                                                       repair ); */

        /* error handling */
        if ( retCode != 0 && repair == 0 ) {
            /* if the code was not well balanced, we will not return 
             * a bad node list, but we have to free the nodes */
            xmlFreeNodeList( nodes );
            nodes = NULL;
        }
        else {
            xmlSetListDoc(nodes,doc);
        }
    }

    return nodes;
}

/** 
 * internal helper: insert node to nodelist
 * synopsis: xmlNodePtr insert_node_to_nodelist( leader, insertnode, followup );
 * while leader and followup are allready list nodes. both may be NULL
 * if leader is null the parents children will be reset
 * if followup is null the parent last will be reset.
 * leader and followup has to be followups in the nodelist!!!
 * the function returns the node inserted. if a fragment was inserted,
 * the first node of the list will returned
 *
 * i ran into a misconception here. there should be a normalization function
 * for the DOM, so sequences of text nodes can get replaced by a single 
 * text node. as i see DOM Level 1 does not allow text node sequences, while
 * Level 2 and 3 do.
 **/
int
domAddNodeToList(xmlNodePtr cur, xmlNodePtr leader, xmlNodePtr followup) 
{
   xmlNodePtr c1 = NULL, c2 = NULL, p = NULL;
   if ( cur ) { 
       c1 = c2 = cur;
       if( leader )
          p = leader->parent;
       else if( followup ) 
          p = followup->parent;
       else
          return(0); /* can't insert */

       if ( cur->type == XML_DOCUMENT_FRAG_NODE ) {
           c1 = cur->children;
           while ( c1 ){
               c1->parent = p;
               c1 = c1->next;
           }  
           c1 = cur->children;
           c2 = cur->last;
           cur->last = cur->children = NULL;
       }
       else {
           cur->parent = p;
       }
       
       if (c1 && c2 && c1!=leader) {
           if ( leader ) {
               leader->next = c1;
	       c1->prev = leader;
           }
           else if ( p ) {
               p->children = c1;
           }
	   
           if ( followup ) {
               followup->prev = c2;
               c2->next = followup;
           }
           else if ( p ) {
               p->last = c2;
           }
       }
       return 1;
   }    
   return 0;
}

/**
 * domIsParent tests, if testnode is parent of the reference
 * node. this test is very important to avoid circular constructs in
 * trees. if the ref is a parent of the cur node the
 * function returns 1 (TRUE), otherwise 0 (FALSE).
 **/
int
domIsParent( xmlNodePtr cur, xmlNodePtr ref ) {
    xmlNodePtr helper = NULL;

    if ( cur == NULL || ref == NULL ) 
        return 0;

    if( cur->doc != ref->doc)
        return 0;

    if( ref->type == XML_DOCUMENT_NODE )
        return 1;

    helper= cur;
    while ( helper && (xmlDocPtr) helper != ref->doc ) {
        if( helper == ref )
            return 1;
        helper = helper->parent;
    }

    return 0;
}

int
domTestHierarchy(xmlNodePtr cur, xmlNodePtr ref) 
{
    if ( !ref || !cur )
        return 0;
    
    switch ( ref->type ){
    case XML_ATTRIBUTE_NODE:
    case XML_DOCUMENT_NODE:
        return 0;
        break;
    case XML_DOCUMENT_FRAG_NODE:
	if ( ref->children == NULL )
            return 0;
	break;
    default:
        break;
    }
    
    if ( cur->type == XML_ATTRIBUTE_NODE )
        return 0;

    if ( domIsParent( cur, ref ) )
	return 0;

    return 1;
}

int
domTestDocument(xmlNodePtr cur, xmlNodePtr ref)
{
    if ( cur->type == XML_DOCUMENT_NODE ) {
        switch ( ref->type ) {
        case XML_ATTRIBUTE_NODE:
        case XML_ELEMENT_NODE:
        case XML_ENTITY_NODE:
        case XML_ENTITY_REF_NODE:
	case XML_TEXT_NODE:
	case XML_CDATA_SECTION_NODE:
	case XML_NAMESPACE_DECL:
            return 0;
            break;
        default:
            break;
        }
    }
    return 1;
}

void
domUnlinkNode( xmlNodePtr node ) {
    if ( node == NULL ) {
        return;
    }

    if ( node->prev != NULL ) {
        node->prev->next = node->next;
    }

    if ( node->next != NULL ) {
        node->next->prev = node->prev;
    }

    if ( node->parent != NULL ) {
        if ( node == node->parent->last ) {
            node->parent->last = node->prev;
        }

        if ( node == node->parent->children ) {
            node->parent->children = node->next;
        }
    }

    node->prev   = NULL;
    node->next   = NULL;
    node->parent = NULL;
}

xmlNodePtr
domImportNode( xmlDocPtr doc, xmlNodePtr node, int move ) {
    xmlNodePtr return_node = node;

    if ( move ) {
        return_node = node;
        if ( node->type != XML_DTD_NODE ) {
            domUnlinkNode( node );
        }
    }
    else {
        if ( node->type == XML_DTD_NODE ) {
            return_node = (xmlNodePtr) xmlCopyDtd((xmlDtdPtr) node);
        }
        else {
            return_node = xmlCopyNode( node, 1 );
        }
    }

    /* tell all children about the new boss */ 
    if ( node && doc && node->doc != doc ) {
        xmlSetTreeDoc(return_node, doc);
    }
 
    return return_node;
}

/**
 * Name: domName
 * Synopsis: string = domName( node );
 *
 * domName returns the full name for the current node.
 * If the node belongs to a namespace it returns the prefix and 
 * the local name. otherwise only the local name is returned.
 **/
xmlChar*
domName(xmlNodePtr node) {
    xmlChar *qname = NULL; 
    if ( node ) {
        if (node->ns != NULL && node->ns->prefix != NULL) {
            xmlChar *tname = xmlStrdup( node->ns->prefix );
            tname = xmlStrcat( tname , ":" );
            tname = xmlStrcat( tname , node->name );
            qname = tname;
        } 
        else {
            qname = xmlStrdup( node->name );
        }
    }

    return qname;
}

/**
 * Name: domAppendChild
 * Synopsis: xmlNodePtr domAppendChild( xmlNodePtr par, xmlNodePtr newCld );
 * @par: the node to append to
 * @newCld: the node to append
 *
 * Returns newCld on success otherwise NULL
 * The function will unbind newCld first if nesseccary. As well the 
 * function will fail, if par or newCld is a Attribute Node OR if newCld 
 * is a parent of par. 
 * 
 * If newCld belongs to a different DOM the node will be imported 
 * implicit before it gets appended. 
 **/
xmlNodePtr
domAppendChild( xmlNodePtr self,
                xmlNodePtr newChild ){
    if ( self == NULL ) {
        return newChild;
    }

    if ( !(domTestHierarchy(self, newChild)
           && domTestDocument(self, newChild))){
        xs_warn("HIERARCHIY_REQUEST_ERR\n"); 
        return NULL;
    }

    if ( newChild->doc == self->doc ){
        domUnlinkNode( newChild ); 
    }
    else {
        xs_warn("WRONG_DOCUMENT_ERR - non conform implementation\n"); 
        newChild= domImportNode( self->doc, newChild, 1 );
    }
 
    if ( self->children != NULL ) {
        xs_warn("unlink node!\n");
        domAddNodeToList( newChild, self->last, NULL );
    }
    else if (newChild->type == XML_DOCUMENT_FRAG_NODE ) {
        xmlNodePtr c1 = NULL;
        newChild->children->parent = self;
        self->children = newChild->children;
        c1 = newChild->children;
        while ( c1 ){
            c1->parent = self;
            c1 = c1->next;
        }  
        self->last = newChild->last;
        newChild->last = newChild->children = NULL;
    }
    else {
        self->children = newChild;
        self->last     = newChild;
        newChild->parent= self;
    }
    
    return newChild;
}

xmlNodePtr
domRemoveChild( xmlNodePtr self, xmlNodePtr old ) {
    if ( self  
         && old 
	 && old->type != XML_ATTRIBUTE_NODE
	 && old->type != XML_NAMESPACE_DECL
         && (self == old->parent)) {
        domUnlinkNode( old );
    }
    return old ;
}

xmlNodePtr
domReplaceChild( xmlNodePtr self, xmlNodePtr new, xmlNodePtr old ) {
    if ( self== NULL )
        return NULL;

    if ( new == old ) 
        return new;
 
    if ( new == NULL ) {
        /* level2 sais nothing about this case :( */
        return domRemoveChild( self, old );
    }

    if ( old == NULL ) {
        domAppendChild( self, new );
        return old;
    }

    if ( !(domTestHierarchy(self, new)
           && domTestDocument(self, new))){
        xs_warn("HIERARCHIY_REQUEST_ERR\n"); 
        return NULL;
    }
    
    if ( new->doc == self->doc ) {
        domUnlinkNode( new );
    }
    else {
        /* WRONG_DOCUMENT_ERR - non conform implementation */
        new = domImportNode( self->doc, new, 1 );
    }
    
    if( old == self->children && old == self->last ) {
        domRemoveChild( self, old );
        domAppendChild( self, new );
    }
    else {
        domAddNodeToList(new, old->prev, old->next );
        old->parent = old->next = old->prev = NULL;    
    }

    return old;
}


xmlNodePtr
domInsertBefore( xmlNodePtr self, 
                 xmlNodePtr newChild,
                 xmlNodePtr refChild ){

    if ( refChild == newChild ) 
        return newChild;
    
    if ( self == NULL || newChild == NULL ) 
        return NULL;
   
    if ( refChild == NULL ) {
        return domAppendChild( self, newChild );
    }

    if ( refChild->parent != self
       || (  newChild->type     == XML_DOCUMENT_FRAG_NODE 
          && newChild->children == NULL ) ) {
        /* NOT_FOUND_ERR */
        return NULL;
    }

    if ( !(domTestHierarchy( self, newChild )
           && domTestDocument( self, newChild ))) {
        return NULL;
    }

    if ( self->doc == newChild->doc ){
        domUnlinkNode( newChild );
    }
    else {
        newChild = domImportNode( self->doc, newChild, 1 );
    }
    
    domAddNodeToList(newChild, refChild->prev, refChild);
    return newChild;
}

/*
 * this function does not exist in the spec although it's useful
 */
xmlNodePtr
domInsertAfter( xmlNodePtr self, 
                xmlNodePtr newChild,
                xmlNodePtr refChild ){
    if ( self == NULL || newChild == NULL ) 
        return NULL;

    if ( refChild == newChild ) 
        return newChild;
    
    if ( refChild == NULL ) {
        return domAppendChild( self, newChild );
    }

    if ( refChild->parent != self
       || (  newChild->type     == XML_DOCUMENT_FRAG_NODE 
          && newChild->children == NULL ) ) {
        /* NOT_FOUND_ERR */
        return NULL;
    }

    if ( !(domTestHierarchy( self, newChild )
           && domTestDocument( self, newChild ))) {
        return NULL;
    }

    if ( self->doc == newChild->doc ){
        domUnlinkNode( newChild );
    }
    else {
        newChild = domImportNode( self->doc, newChild, 1 );
    }

    domAddNodeToList(newChild, refChild, refChild->next);
    return newChild;
}

xmlNodePtr
domReplaceNode( xmlNodePtr oldNode, xmlNodePtr newNode ) {
    xmlNodePtr prev = NULL, next = NULL, par = NULL;
    
    if ( oldNode == NULL
         || newNode == NULL ) {
        /* NOT_FOUND_ERROR */
        return NULL;
    } 

    if ( oldNode->type == XML_ATTRIBUTE_NODE
         || newNode->type == XML_ATTRIBUTE_NODE
         || newNode->type == XML_DOCUMENT_NODE
         || domIsParent( newNode, oldNode ) ) {
        /* HIERARCHY_REQUEST_ERR
         * wrong node type
         * new node is parent of itself
         */
        return NULL;
    }
        
    par  = oldNode->parent;
    prev = oldNode->prev;
    next = oldNode->next;

    if ( oldNode->_private == NULL ) {
        xmlUnlinkNode( oldNode );
    }
    else {
        domUnlinkNode( oldNode );
    }

    if( prev == NULL && next == NULL ) {
        /* oldNode was the only child */
        domAppendChild( par ,newNode ); 
    }
    else {
        domAddNodeToList( newNode, prev,  next );
    }

    return oldNode;
}

xmlChar*
domGetNodeValue( xmlNodePtr n ) {
    xmlChar * retval = NULL;
    if( n != NULL ) {
        switch ( n->type ) {
        case XML_ATTRIBUTE_NODE:
        case XML_ENTITY_DECL:
        case XML_TEXT_NODE:
        case XML_COMMENT_NODE:
        case XML_CDATA_SECTION_NODE:
        case XML_PI_NODE:
        case XML_ENTITY_REF_NODE:
            break;
        default:
            return retval;
            break;
        }
        if ( n->type != XML_ENTITY_DECL ) {
            retval = xmlXPathCastNodeToString(n);
        }
        else {
            if ( n->content != NULL ) {
                xs_warn(" dublicate content\n" );
                retval = xmlStrdup(n->content);
            }
            else if ( n->children != NULL ) {
                xmlNodePtr cnode = n->children;
                xs_warn(" use child content\n" );
                /* ok then toString in this case ... */
                while (cnode) {
                    xmlBufferPtr buffer = xmlBufferCreate();
                    /* buffer = xmlBufferCreate(); */
                    xmlNodeDump( buffer, n->doc, cnode, 0, 0 );
                    if ( buffer->content != NULL ) {
                        xs_warn( "add item" );
                        if ( retval != NULL ) {
                            retval = xmlStrcat( retval, buffer->content );
                        }
                        else {
                            retval = xmlStrdup( buffer->content );
                        }
                    }
                    xmlBufferFree( buffer );
                    cnode = cnode->next;
                }
            }
        }
    }

    return retval;
}

void
domSetNodeValue( xmlNodePtr n , xmlChar* val ){
    if ( n == NULL ) 
        return;
    if ( val == NULL ){
        val = "";
    }
  
    if( n->type == XML_ATTRIBUTE_NODE ){
        if ( n->children != NULL ) {
            n->last = NULL;
            xmlFreeNodeList( n->children );
        }
        n->children = xmlNewText( val );
        n->children->parent = n;
        n->children->doc = n->doc;
        n->last = n->children; 
    }
    else if( n->content != NULL ) {
        /* free old content */
        xmlFree( n->content );
        n->content = xmlStrdup(val);   
    }
}


void
domSetParentNode( xmlNodePtr self, xmlNodePtr p ) {
    /* never set the parent to a node in the own subtree */ 
    if( self && !domIsParent(self, p)) {
        if( self->parent != p ){
            xmlUnlinkNode( self );
            self->parent = p;
            if( p->doc != self->doc ) {
                self->doc = p->doc;
            }
        }
    }
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

xmlNsPtr
domNewNs ( xmlNodePtr elem , xmlChar *prefix, xmlChar *href ) {
    xmlNsPtr ns = NULL;
  
    if (elem != NULL) {
        ns = xmlSearchNs( elem->doc, elem, prefix );
    }
    /* prefix is not in use */
    if (ns == NULL) {
        ns = xmlNewNs( elem , href , prefix );
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
/* prolly not required anymore ... */
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
    xmlAttrPtr prop = NULL;
    xmlDocPtr doc = NULL;
    xmlNsPtr ns = NULL;
    
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

xmlAttrPtr 
domSetAttributeNode( xmlNodePtr node, xmlAttrPtr attr ) {
    if ( node == NULL || attr == NULL ) {
        return attr;
    }
    if ( attr != NULL && attr->type != XML_ATTRIBUTE_NODE )
        return NULL;
    if ( node == attr->parent ) {
        return attr; /* attribute is allready part of the node */
    }  
    if ( attr->doc != node->doc ){
        attr = (xmlAttrPtr) domImportNode( node->doc, (xmlNodePtr) attr, 1 ); 
    } 
    else {
        xmlUnlinkNode( (xmlNodePtr) attr );
    }

    /* stolen from libxml2 */
    if ( attr != NULL ) {
        if (node->properties == NULL) {
            node->properties = attr;
        } else {
            xmlAttrPtr prev = node->properties;
            
            while (prev->next != NULL) prev = prev->next;
            prev->next = attr;
            attr->prev = prev;
        }
    }

    return attr;
}

int
domNodeNormalize( xmlNodePtr node )
{
    xmlNodePtr next = NULL;

    if ( node == NULL ) 
        return(0);

    switch ( node->type ) {
    case XML_TEXT_NODE:
        while ( node->next
                && node->next->type == XML_TEXT_NODE ) {
            next = node->next;
            xmlNodeAddContent(node, next->content);
            xmlUnlinkNode( next );

            /**
             * keep only nodes that are refered by perl (or GDOME)
             */
            if ( !next->_private )
                xmlFreeNode( next );
        }
        break;
    case XML_ELEMENT_NODE:
        domNodeNormalizeList( (xmlNodePtr) node->properties );
    case XML_ATTRIBUTE_NODE:
        return( domNodeNormalizeList( node->children ) );
        break;
    default:
        break;
    }    
    return(1);
}

int
domNodeNormalizeList( xmlNodePtr nodelist )
{
    if ( nodelist == NULL ) 
        return(0);

    while ( nodelist ){
        if ( domNodeNormalize( nodelist ) == 0 )
            return(0);
        nodelist = nodelist->next;
    }
    return(1);
}
